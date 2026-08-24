defmodule Storyarn.Billing.StorageAccountingTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageAccounting
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotRestore
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workers.ProjectSnapshotRetentionWorker

  @checksum String.duplicate("a", 64)

  setup do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)

    %{user: user, project: project, workspace: project.workspace}
  end

  describe "authoritative usage projection" do
    test "sums mutually exclusive logical assets, snapshots, and active reservations", context do
      asset_fixture(context.project, context.user, %{size: 2_000})

      context.project
      |> asset_fixture(context.user, %{size: 500})
      |> Asset.trash_changeset(context.user.id, "user", TimeHelpers.now())
      |> Repo.update!()

      full_snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 100, metadata: 20, assets: 50})

      assert {:ok, reservation} =
               reserve(context, "restore", "restore_staging", 30, full_snapshot)

      usage = Billing.workspace_storage_usage(context.workspace.id)

      assert usage.current_assets == %{bytes: 2_000, count: 1}
      assert usage.asset_trash == %{bytes: 500, count: 1}
      assert usage.full_snapshots == %{bytes: 170, count: 1}
      assert usage.active_reservations.bytes == 30
      assert usage.active_reservations.by_kind == %{"restore_staging" => 30}
      assert usage.accounted_bytes == 2_700

      project_usage = Billing.project_storage_usage(context.project.id)
      assert project_usage.current_assets == %{bytes: 2_000, count: 1}
      assert project_usage.asset_trash == %{bytes: 500, count: 1}
      assert project_usage.accounted_bytes == 2_700

      assert {:ok, _released} =
               Billing.release_storage_reservation(reservation.id, reservation.lease_token, reservation.generation, %{
                 reason: "restore cancelled before staging",
                 cleanup_status: "not_required",
                 cleanup_proof: no_write_proof(reservation)
               })

      assert Billing.workspace_storage_usage(context.workspace.id).accounted_bytes == 2_670
    end

    test "charges one unique blob within a full snapshot and charges separate snapshots independently", context do
      first = insert_full_snapshot!(context.project, 1, %{project: 100, metadata: 20, assets: 50}, 2, 1)
      second = insert_full_snapshot!(context.project, 2, %{project: 100, metadata: 20, assets: 50}, 2, 1)

      assert first.asset_count == 2
      assert first.blob_count == 1
      assert first.asset_blob_size_bytes == 50
      assert second.asset_blob_size_bytes == 50

      usage = Billing.workspace_storage_usage(context.workspace.id)
      assert usage.full_snapshots == %{bytes: 340, count: 2}
      assert usage.accounted_bytes == 340
    end

    test "keeps a deleting snapshot accounted until durable ownership is removed", context do
      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 100, metadata: 20, assets: 50})

      snapshot
      |> ProjectSnapshot.deletion_changeset(TimeHelpers.now())
      |> Repo.update!()

      usage = Billing.workspace_storage_usage(context.workspace.id)
      assert usage.full_snapshots == %{bytes: 170, count: 1}
      assert usage.accounted_bytes == 170
    end

    test "retains logical asset charges while a project is recoverable from project trash", context do
      trashed_project = project_fixture(context.user, workspace: context.workspace)
      asset_fixture(trashed_project, context.user, %{size: 4_096})

      before = Billing.workspace_storage_usage(context.workspace.id)

      trashed_project
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      after_trash = Billing.workspace_storage_usage(context.workspace.id)
      assert after_trash.current_assets == before.current_assets
      assert after_trash.accounted_bytes == before.accounted_bytes
    end

    test "provider objects and reported footprint never change product quota", context do
      before = Billing.workspace_storage_usage(context.workspace.id)
      key = "accounting-tests/orphan/#{Ecto.UUID.generate()}"
      assert {:ok, _url} = Storage.upload(key, "orphan provider bytes", "application/octet-stream")

      handler_id = "storage-accounting-provider-#{Ecto.UUID.generate()}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :storage, :provider_footprint],
          fn event, measurements, metadata, receiver ->
            send(receiver, {event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        Storage.delete(key)
      end)

      assert :ok =
               Billing.emit_provider_storage_footprint(context.workspace.id, %{
                 physical_bytes: 10_000,
                 orphan_bytes: 10_000
               })

      assert_receive {
        [:storyarn, :storage, :provider_footprint],
        %{physical_bytes: 10_000, orphan_bytes: 10_000},
        %{workspace_id: workspace_id}
      }

      assert workspace_id == context.workspace.id
      assert Billing.workspace_storage_usage(context.workspace.id).accounted_bytes == before.accounted_bytes
    end

    test "successful accounting mutations emit the product-accounted projection", context do
      handler_id = "storage-accounting-updated-#{Ecto.UUID.generate()}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :storage, :accounting, :updated],
          fn event, measurements, metadata, receiver ->
            send(receiver, {event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      assert {:ok, _reservation} = reserve(context, "telemetry", "snapshot_export", 100, snapshot)

      assert_receive {
        [:storyarn, :storage, :accounting, :updated],
        %{accounted_bytes: 30, reservation_bytes: 100, total_bytes: 130},
        %{workspace_id: workspace_id, action: :reserved, accounting_version: 1}
      }

      assert workspace_id == context.workspace.id
    end
  end

  describe "reservations" do
    test "replays an exact idempotency key and rejects a conflicting replay", context do
      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      attrs = reservation_attrs(context, "same", "restore_staging", 1_024, snapshot)

      assert {:ok, first} = Billing.reserve_storage(attrs)
      assert {:ok, replayed} = Billing.reserve_storage(attrs)
      assert replayed.id == first.id
      assert replayed.lease_token == first.lease_token
      assert replayed.project_snapshot_id_snapshot == snapshot.id

      assert String.starts_with?(
               replayed.storage_namespace,
               "projects/#{context.project.id}/storage-reservations/v1/restore-staging/"
             )

      assert {:error, :reservation_conflict} =
               attrs
               |> Map.put(:reserved_bytes, 2_048)
               |> Billing.reserve_storage()

      assert Repo.aggregate(
               from(reservation in StorageReservation,
                 where: reservation.workspace_id_snapshot == ^context.workspace.id
               ),
               :count
             ) == 1
    end

    test "preserves immutable snapshot attribution when the live target is deleted", context do
      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, reservation} =
               reserve(context, "target-copy", "snapshot_export", 100, snapshot)

      Repo.delete!(snapshot)

      retained = Repo.get!(StorageReservation, reservation.id)
      assert is_nil(retained.project_snapshot_id)
      assert retained.project_snapshot_id_snapshot == snapshot.id

      assert Billing.active_storage_reservations_by_snapshot([snapshot.id]) == %{
               snapshot.id => %{active_bytes: 100, export_bytes: 100, active_count: 1}
             }
    end

    test "rejects an exact idempotency replay after its lease expires", context do
      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      attrs = reservation_attrs(context, "expired-replay", "snapshot_export", 100, snapshot)
      assert {:ok, reservation} = Billing.reserve_storage(attrs)

      measured_at = DateTime.add(TimeHelpers.now(), -2, :second)

      reservation
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(measured_at, 1, :second),
        accounting_measured_at: measured_at
      )
      |> Repo.update!()

      assert {:error, :storage_reservation_lease_expired} = Billing.reserve_storage(attrs)

      usage = Billing.workspace_storage_usage(context.workspace.id)
      assert usage.active_reservations.bytes == 100
      assert usage.accounted_bytes == 130
    end

    test "extends atomically and fails closed when final bytes are underestimated", context do
      pending_snapshot =
        insert_pending_snapshot!(context.project, 1, %{project: 70, metadata: 20, assets: 30})

      assert {:ok, reservation} =
               reserve(context, "build", "snapshot_build", 100, pending_snapshot)

      prepare_build_publication!(
        reservation,
        full_snapshot_object_set_attrs(
          pending_snapshot,
          %{project: 70, metadata: 20, assets: 30}
        )
      )

      parent = self()

      assert {:error, :reservation_underestimated, details} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 120,
                 fn _reservation ->
                   send(parent, :owner_published)
                   {:ok, :published}
                 end
               )

      assert details.reserved_bytes == 100
      assert details.actual_bytes == 120
      refute_receive :owner_published
      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      assert {:ok, extended} =
               Billing.extend_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 120
               )

      assert extended.reserved_bytes == 120
      assert extended.generation == reservation.generation + 1

      assert {:ok, %{result: snapshot, reservation: committed}} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 extended.generation,
                 120,
                 fn _reservation ->
                   {:ok,
                    finalize_pending_full_snapshot!(
                      pending_snapshot,
                      %{project: 70, metadata: 20, assets: 30}
                    )}
                 end
               )

      assert snapshot.id == pending_snapshot.id
      assert snapshot.accounted_size_bytes == 120
      assert committed.status == "committed"
      assert committed.project_snapshot_id == snapshot.id
      assert committed.actual_bytes == 120

      usage = Billing.workspace_storage_usage(context.workspace.id)
      assert usage.active_reservations.bytes == 0
      assert usage.full_snapshots.bytes == 120
      assert usage.accounted_bytes == 120

      assert {:ok, %{result: :already_committed}} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 extended.generation,
                 120,
                 fn _reservation -> flunk("idempotent commit must not run ownership callback") end
               )
    end

    test "allows only one active build reservation per snapshot", context do
      pending_snapshot = insert_pending_snapshot!(context.project, 1)

      assert {:ok, build} =
               reserve(context, "exclusive-build", "snapshot_build", 100, pending_snapshot)

      assert {:error, :storage_reservation_active_for_snapshot} =
               reserve(context, "competing-build", "snapshot_build", 100, pending_snapshot)

      {_cleanup_request, cleanup_scope} = insert_cleanup_scope!(build)

      assert {:ok, _released} =
               Billing.release_storage_reservation(
                 build.id,
                 build.lease_token,
                 build.generation,
                 %{
                   reason: "retrying the build",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_scope.cleanup_request_id,
                   cleanup_scope: cleanup_scope
                 }
               )

      retry_target = insert_pending_snapshot!(context.project, 2)

      assert {:ok, retried_build} =
               reserve(context, "competing-build", "snapshot_build", 100, retry_target)

      assert retried_build.id != build.id
    end

    test "rejects cross-workspace attribution before holding capacity", context do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      other_target = insert_pending_snapshot!(other_project, 1)

      assert {:error, :invalid_storage_reservation_project} =
               context
               |> reservation_attrs("cross-workspace", "snapshot_build", 100, other_target)
               |> Map.put(:project_id, other_project.id)
               |> Billing.reserve_storage()

      assert Repo.aggregate(
               from(reservation in StorageReservation,
                 where: reservation.workspace_id_snapshot == ^context.workspace.id
               ),
               :count
             ) == 0
    end

    test "allows restore staging for a recoverable project but blocks other operations", context do
      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      context.project
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      restore_attrs =
        reservation_attrs(context, "recoverable-restore", "restore_staging", 100, snapshot)

      assert {:ok, reservation} = Billing.reserve_storage(restore_attrs)
      assert {:ok, replayed} = Billing.reserve_storage(restore_attrs)
      assert replayed.id == reservation.id

      assert {:error, :invalid_storage_reservation_project} =
               context
               |> reservation_attrs("deleted-export", "snapshot_export", 100, snapshot)
               |> Billing.reserve_storage()
    end

    test "rolls back a verified owner different from the reserved snapshot target", context do
      target = insert_pending_snapshot!(context.project, 1)
      different_target = insert_pending_snapshot!(context.project, 2)

      assert {:ok, reservation} =
               reserve(context, "owner-mismatch", "snapshot_build", 100, target)

      prepare_build_publication!(reservation)

      assert {:error, :storage_reservation_owner_mismatch} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100,
                 fn _reservation -> {:ok, different_target} end
               )

      assert Repo.get!(StorageReservation, reservation.id).status == "active"
      assert Repo.get!(ProjectSnapshot, target.id).lifecycle_state == "pending"
      assert Repo.get!(ProjectSnapshot, different_target.id).lifecycle_state == "pending"
    end

    test "a build cannot commit ready ownership without its exact published claim", context do
      target = insert_pending_snapshot!(context.project, 1)
      assert {:ok, reservation} = reserve(context, "unpublished", "snapshot_build", 100, target)
      mark_reservation_started!(reservation)
      parent = self()

      assert {:error, :snapshot_object_publication_not_ready} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100,
                 fn _reservation ->
                   send(parent, :owner_called)
                   {:ok, target}
                 end
               )

      refute_receive :owner_called

      insert_publication_claim!(reservation, "staged")

      assert {:error, :snapshot_object_publication_not_ready} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100,
                 fn _reservation -> flunk("a staged claim is not durable ready ownership") end
               )

      assert Repo.get!(StorageReservation, reservation.id).status == "active"
      assert Repo.get!(ProjectSnapshot, target.id).lifecycle_state == "pending"
    end

    test "a build cannot commit snapshot metadata that differs from its published inventory", context do
      target =
        insert_pending_snapshot!(context.project, 1, %{project: 60, metadata: 20, assets: 20})

      assert {:ok, reservation} = reserve(context, "inventory-mismatch", "snapshot_build", 100, target)

      prepare_build_publication!(
        reservation,
        full_snapshot_object_set_attrs(target, %{project: 70, metadata: 20, assets: 10})
      )

      assert {:error, :storage_reservation_owner_mismatch} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100,
                 fn _reservation ->
                   {:ok,
                    finalize_pending_full_snapshot!(
                      target,
                      %{project: 60, metadata: 20, assets: 20}
                    )}
                 end
               )

      assert Repo.get!(StorageReservation, reservation.id).status == "active"
      assert Repo.get!(ProjectSnapshot, target.id).lifecycle_state == "pending"
    end

    test "a build commit rolls back when lifecycle generation advances before finalization", context do
      target =
        context.project
        |> insert_pending_snapshot!(1, %{project: 60, metadata: 20, assets: 20})
        |> transition_pending_snapshot_to_verifying!()

      final_attrs =
        full_snapshot_object_set_attrs(target, %{project: 60, metadata: 20, assets: 20})

      assert {:ok, reservation} =
               reserve(context, "stale-lifecycle-generation", "snapshot_build", 100, target)

      prepare_build_publication!(reservation, final_attrs)

      advanced =
        target
        |> ProjectSnapshot.cancel_request_changeset(TimeHelpers.now())
        |> Repo.update!()

      assert advanced.lifecycle_generation == target.lifecycle_generation + 1

      assert {:error, :stale_snapshot_accounting_measurement} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100,
                 fn _reservation ->
                   Versioning.finalize_project_snapshot_object_set(
                     target.id,
                     0,
                     final_attrs
                   )
                 end
               )

      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      persisted = Repo.get!(ProjectSnapshot, target.id)
      assert persisted.lifecycle_generation == advanced.lifecycle_generation
      assert persisted.lifecycle_state == "verifying"
      assert is_nil(persisted.accounted_size_bytes)
    end

    test "same-size renewal is idempotent without letting stale workers cross the generation fence", context do
      target = insert_pending_snapshot!(context.project, 1)

      assert {:ok, reservation} =
               reserve(context, "fencing", "snapshot_build", 100, target)

      assert {:ok, renewed} =
               Billing.extend_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100
               )

      assert renewed.generation == reservation.generation + 1
      assert DateTime.after?(renewed.expires_at, reservation.expires_at)

      assert {:ok, replayed} =
               Billing.extend_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100
               )

      assert replayed.id == renewed.id
      assert replayed.generation == renewed.generation
      assert replayed.expires_at == renewed.expires_at

      assert {:error, :storage_reservation_generation_mismatch} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 100,
                 fn _reservation -> flunk("a stale worker must not publish ownership") end
               )

      measured_at = DateTime.add(TimeHelpers.now(), -2, :second)

      mark_reservation_started!(renewed)

      renewed
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(measured_at, 1, :second),
        accounting_measured_at: measured_at
      )
      |> Repo.update!()

      assert {:error, :storage_reservation_lease_expired} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 renewed.generation,
                 100,
                 fn _reservation -> flunk("an expired worker must not publish ownership") end
               )
    end

    test "a terminal idempotency key cannot be mistaken for active capacity", context do
      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      attrs = reservation_attrs(context, "terminal", "restore_staging", 100, snapshot)
      assert {:ok, reservation} = Billing.reserve_storage(attrs)

      assert {:ok, released} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "cancelled before storage",
                   cleanup_status: "not_required",
                   cleanup_proof: no_write_proof(reservation)
                 }
               )

      assert released.status == "released"
      assert {:error, :storage_reservation_terminal} = Billing.reserve_storage(attrs)
    end

    test "snapshot slots count a build target once and exclude terminal targets without an active reservation", context do
      target = insert_pending_snapshot!(context.project, 1)

      assert {:ok, reservation} =
               reserve(context, "slot", "snapshot_build", 1, target)

      {_cleanup_request, cleanup_scope} = insert_cleanup_scope!(reservation)

      usage = Billing.project_limits_usage(context.project)
      assert usage.project.project_snapshots.used == 1

      now = TimeHelpers.now()

      target
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "building",
        progress_phase: "copying",
        building_started_at: now,
        state_updated_at: now
      })
      |> Repo.update!()
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "failed",
        progress_phase: "failed",
        failure_code: "build_failed",
        failure_message: "Snapshot build failed.",
        failed_at: now,
        state_updated_at: now
      })
      |> Repo.update!()

      usage_with_active_reservation = Billing.project_limits_usage(context.project)
      assert usage_with_active_reservation.project.project_snapshots.used == 1

      assert {:ok, _released} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "build failed",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_scope.cleanup_request_id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert Billing.project_limits_usage(context.project).project.project_snapshots.used == 0

      cancelled_at = TimeHelpers.now()

      context.project
      |> insert_pending_snapshot!(2)
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "cancelled",
        progress_phase: "cancelled",
        cancelled_at: cancelled_at,
        state_updated_at: cancelled_at
      })
      |> Repo.update!()

      assert Billing.project_limits_usage(context.project).project.project_snapshots.used == 0
    end

    test "the pending build represented at the exact snapshot limit can reserve its slot", context do
      limit = Billing.plan_limit(Billing.default_plan(), :project_snapshots_per_project)

      for version <- 1..(limit - 1) do
        insert_full_snapshot!(context.project, version, %{project: 10, metadata: 10, assets: 10})
      end

      boundary_target = insert_pending_snapshot!(context.project, limit)

      assert {:ok, _reservation} =
               reserve(context, "boundary-slot", "snapshot_build", 1, boundary_target)

      over_limit_target = insert_pending_snapshot!(context.project, limit + 1)

      assert {:error, :snapshot_limit_reached, %{resource: :project_snapshots_per_project, used: used, limit: ^limit}} =
               reserve(context, "over-limit-slot", "snapshot_build", 1, over_limit_target)

      assert used == limit + 1
    end

    test "a reservation reduces availability for synchronous asset uploads", context do
      limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)

      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      insert_asset_row!(context, limit - snapshot.accounted_size_bytes - 100)

      assert {:ok, _reservation} =
               reserve(context, "capacity", "restore_staging", 60, snapshot)

      assert :ok = Billing.can_upload_asset?(context.workspace, 40)

      used = limit - 40

      assert {:error, :limit_reached, %{used: ^used, required: 41, available: 40, limit: ^limit, reserved: 60}} =
               Billing.can_upload_asset?(context.workspace, 41)
    end

    test "owned cleanup accepts only canonical keys in the build's exact archive namespaces", context do
      snapshot = insert_pending_snapshot!(context.project, 1)

      assert {:ok, reservation} =
               reserve(context, "cleanup", "snapshot_build", 100, snapshot)

      assert reservation.cleanup_object_prefix == snapshot.object_prefix
      assert {:ok, prefixes} = StorageAccounting.operation_object_prefixes(reservation)
      assert prefixes.ready == snapshot.object_prefix
      assert String.contains?(prefixes.staging, "/staging/")

      assert {:error, :storage_reservation_cleanup_ownership_required} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "staging failed",
                   cleanup_status: "owned",
                   cleanup_reference: "freeform-cleanup-owner"
                 }
               )

      assert {:error, :storage_reservation_cleanup_ownership_required} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{reason: "staging failed", cleanup_status: "not_required"}
               )

      unrelated_request =
        Repo.insert!(%StorageCleanupRequest{
          storage_keys: [
            "projects/#{context.project.id}/snapshots/archives/v2/ready/AAAAAAAAAAAAAAAA/snapshot.zip"
          ]
        })

      assert {:error, :storage_reservation_cleanup_ownership_required} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "staging failed",
                   cleanup_status: "owned",
                   cleanup_request_id: unrelated_request.id
                 }
               )

      {cleanup_request, cleanup_scope} =
        insert_cleanup_scope!(reservation, ["snapshot.zip", "manifest.json"])

      assert {:ok, released} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "staging failed",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert released.cleanup_reference == "storage_cleanup_request:#{cleanup_request.id}"

      Repo.delete!(cleanup_request)

      assert {:ok, replayed} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "staging failed",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert replayed.id == released.id
      assert replayed.generation == released.generation
    end

    test "lower runtime limits cannot strand an already committed cleanup inventory", context do
      snapshot = insert_pending_snapshot!(context.project, 1)
      assert {:ok, reservation} = reserve(context, "limit-drift-cleanup", "snapshot_build", 100, snapshot)

      mark_reservation_started!(reservation)
      insert_publication_claim!(reservation, "poisoned")

      original_limits = Application.get_env(:storyarn, SnapshotObjectFormat, [])
      Application.put_env(:storyarn, SnapshotObjectFormat, Keyword.put(original_limits, :max_objects, 0))
      on_exit(fn -> Application.put_env(:storyarn, SnapshotObjectFormat, original_limits) end)

      {cleanup_request, cleanup_scope} = insert_cleanup_scope!(reservation)

      assert {:ok, released} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "build failed after a limit change",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert released.status == "released"
    end

    test "non-build reservations own an exact temporary cleanup namespace", context do
      snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, reservation} =
               reserve(context, "restore-cleanup", "restore_staging", 100, snapshot)

      assert {:ok, %{temporary: temporary_prefix}} =
               StorageAccounting.operation_object_prefixes(reservation)

      assert temporary_prefix == reservation.storage_namespace
      assert reservation.cleanup_object_prefix == reservation.storage_namespace

      cleanup_request =
        Repo.insert!(%StorageCleanupRequest{
          storage_keys: [snapshot.object_prefix <> "/project.json"]
        })

      assert {:error, :storage_reservation_cleanup_ownership_required} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "restore staging failed",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id
                 }
               )

      {cleanup_request, cleanup_scope} = insert_cleanup_scope!(reservation, ["restore.json"])

      assert {:ok, released} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "restore staging failed",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert released.cleanup_reference == "storage_cleanup_request:#{cleanup_request.id}"
    end

    test "database rejects a started reservation with a null cleanup digest", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      assert {:ok, reservation} = reserve(context, "null-digest", "restore_staging", 100, snapshot)
      marked = mark_reservation_started!(reservation, ["restore.json"])

      changeset =
        marked
        |> Ecto.Changeset.change(cleanup_inventory_digest: nil)
        |> Ecto.Changeset.check_constraint(:cleanup_inventory_digest,
          name: :workspace_storage_reservations_cleanup_inventory_commitment
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{cleanup_inventory_digest: [_]} = errors_on(rejected)
    end

    test "database rejects a released reservation with null cleanup status", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      assert {:ok, reservation} = reserve(context, "null-cleanup-status", "snapshot_export", 100, snapshot)

      assert {:ok, released} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "cancelled before export",
                   cleanup_status: "not_required",
                   cleanup_proof: no_write_proof(reservation)
                 }
               )

      changeset =
        released
        |> Ecto.Changeset.change(cleanup_status: nil)
        |> Ecto.Changeset.check_constraint(:cleanup_status,
          name: :workspace_storage_reservations_terminal_fields
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{cleanup_status: [_]} = errors_on(rejected)
    end

    test "database rejects a temporary reservation with a null cleanup prefix", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      assert {:ok, reservation} = reserve(context, "null-prefix", "restore_staging", 100, snapshot)

      assert_raise Postgrex.Error, ~r/cleanup_object_prefix/, fn ->
        reservation
        |> Ecto.Changeset.change(cleanup_object_prefix: nil)
        |> Repo.update!()
      end
    end

    test "database keeps publication claim identity and inventory immutable", context do
      target = insert_pending_snapshot!(context.project, 1)
      assert {:ok, reservation} = reserve(context, "immutable-claim", "snapshot_build", 100, target)
      prepare_build_publication!(reservation)
      claim = Repo.get!(SnapshotObjectPublicationClaim, reservation.cleanup_object_prefix)

      assert_raise Postgrex.Error, ~r/publication claim identity is immutable/, fn ->
        claim
        |> Ecto.Changeset.change(inventory_digest: String.duplicate("f", 64))
        |> Repo.update!()
      end
    end

    test "database rejects backwards publication claim transitions", context do
      target = insert_pending_snapshot!(context.project, 1)
      assert {:ok, reservation} = reserve(context, "backwards-claim", "snapshot_build", 100, target)
      prepare_build_publication!(reservation)
      claim = Repo.get!(SnapshotObjectPublicationClaim, reservation.cleanup_object_prefix)

      assert_raise Postgrex.Error, ~r/state cannot move backwards/, fn ->
        claim
        |> Ecto.Changeset.change(
          status: "publishing",
          lease_expires_at: DateTime.add(TimeHelpers.now(), 3600, :second)
        )
        |> Repo.update!()
      end
    end

    test "releases an orphaned reservation after workspace deletion without weakening fences", context do
      snapshot = insert_pending_snapshot!(context.project, 1)
      assert {:ok, reservation} = reserve(context, "deleted-workspace", "snapshot_build", 100, snapshot)
      {cleanup_request, cleanup_scope} = insert_cleanup_scope!(reservation)

      Repo.delete!(context.workspace)

      orphaned = Repo.get!(StorageReservation, reservation.id)
      assert is_nil(orphaned.workspace_id)
      assert is_nil(orphaned.project_id)
      assert is_nil(orphaned.project_snapshot_id)
      assert orphaned.workspace_id_snapshot == context.workspace.id
      assert orphaned.cleanup_object_prefix == snapshot.object_prefix

      assert {:error, :storage_reservation_lease_mismatch} =
               Billing.release_storage_reservation(
                 orphaned.id,
                 Ecto.UUID.generate(),
                 orphaned.generation,
                 %{
                   reason: "workspace deleted",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert {:error, :storage_reservation_generation_mismatch} =
               Billing.release_storage_reservation(
                 orphaned.id,
                 orphaned.lease_token,
                 orphaned.generation + 1,
                 %{
                   reason: "workspace deleted",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert {:ok, released} =
               Billing.release_storage_reservation(
                 orphaned.id,
                 orphaned.lease_token,
                 orphaned.generation,
                 %{
                   reason: "workspace deleted",
                   cleanup_status: "owned",
                   cleanup_request_id: cleanup_request.id,
                   cleanup_scope: cleanup_scope
                 }
               )

      assert released.status == "released"
      assert released.cleanup_reference == "storage_cleanup_request:#{cleanup_request.id}"
    end
  end

  describe "zero-byte snapshot export leases" do
    test "reserves, renews, and releases behind the lease generation fence", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, lease} =
               reserve(context, "direct-export", "snapshot_export", 0, snapshot)

      assert lease.kind == "snapshot_export"
      assert lease.status == "active"
      assert lease.reserved_bytes == 0
      assert is_nil(lease.storage_started_at)

      assert DateTime.diff(lease.expires_at, lease.accounting_measured_at, :second) ==
               Versioning.project_snapshot_download_export_lease_ttl_seconds()

      assert Billing.active_storage_reservations_by_snapshot([snapshot.id]) == %{
               snapshot.id => %{active_bytes: 0, export_bytes: 0, active_count: 1}
             }

      assert {:error, :zero_byte_snapshot_export_lease_cannot_start_storage} =
               Billing.mark_storage_reservation_started(
                 lease.id,
                 lease.lease_token,
                 lease.generation,
                 %{
                   temporary_prefix: lease.storage_namespace,
                   storage_keys: [lease.storage_namespace <> "/snapshot.zip"]
                 }
               )

      assert {:ok, renewed} =
               Billing.extend_storage_reservation(
                 lease.id,
                 lease.lease_token,
                 lease.generation,
                 0
               )

      assert renewed.generation == lease.generation + 1
      assert DateTime.after?(renewed.expires_at, lease.expires_at)
      lease_ttl = Versioning.project_snapshot_download_export_lease_ttl_seconds()

      assert DateTime.diff(renewed.expires_at, renewed.accounting_measured_at, :second) in lease_ttl..(lease_ttl + 1)
      assert renewed.reserved_bytes == 0
      assert is_nil(renewed.storage_started_at)

      release_attrs = %{
        reason: "snapshot download finished",
        cleanup_status: "not_required",
        cleanup_proof: no_write_proof(renewed)
      }

      assert {:error, :storage_reservation_generation_mismatch} =
               Billing.release_storage_reservation(
                 renewed.id,
                 renewed.lease_token,
                 lease.generation,
                 release_attrs
               )

      assert {:ok, released} =
               Billing.release_storage_reservation(
                 renewed.id,
                 renewed.lease_token,
                 renewed.generation,
                 release_attrs
               )

      assert released.status == "released"
      assert released.generation == renewed.generation + 1
      assert released.cleanup_status == "not_required"
      assert released.cleanup_reference == "storage_not_started:#{lease.storage_namespace}"
    end

    test "coalesced acquisition owns its database-clock expiry contract", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      database_before = database_clock_now()

      attrs =
        context
        |> reservation_attrs("coalesced-export", "snapshot_export", 0, snapshot)
        |> Map.put(:expires_at, DateTime.add(database_before, 30 * 24 * 60 * 60, :second))

      assert {:ok, first} = Billing.acquire_snapshot_export_lease(attrs)
      database_after = database_clock_now()

      assert DateTime.compare(first.accounting_measured_at, database_before) in [:eq, :gt]
      assert DateTime.compare(first.accounting_measured_at, database_after) in [:eq, :lt]

      assert DateTime.diff(first.expires_at, first.accounting_measured_at, :second) ==
               Versioning.project_snapshot_download_export_lease_ttl_seconds()

      assert DateTime.before?(first.expires_at, DateTime.add(database_before, 30 * 24 * 60 * 60, :second))

      assert {:ok, second} =
               context
               |> reservation_attrs("second-coalesced-export", "snapshot_export", 0, snapshot)
               |> Map.put(:expires_at, DateTime.add(database_before, 60 * 24 * 60 * 60, :second))
               |> Billing.acquire_snapshot_export_lease()

      assert second.id == first.id
      assert second.generation == first.generation + 1

      lease_ttl = Versioning.project_snapshot_download_export_lease_ttl_seconds()

      assert DateTime.diff(second.expires_at, second.accounting_measured_at, :second) in lease_ttl..(lease_ttl + 1)
    end

    test "keeps the standard TTL for positive snapshot export reservations", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, reservation} =
               reserve(context, "persisted-export", "snapshot_export", 100, snapshot)

      assert DateTime.diff(reservation.expires_at, reservation.accounting_measured_at, :second) == 24 * 60 * 60
    end

    test "rejects zero-byte snapshot builds but permits an asset-free restore", context do
      pending = insert_pending_snapshot!(context.project, 1)
      full = insert_full_snapshot!(context.project, 2, %{project: 10, metadata: 10, assets: 10})

      assert {:error, :invalid_storage_reservation_snapshot} =
               reserve(context, "zero-build", "snapshot_build", 0, pending)

      assert {:ok, restore} = reserve(context, "zero-restore", "restore_staging", 0, full)
      assert restore.reserved_bytes == 0
      assert restore.kind == "restore_staging"
    end

    test "commits a zero-byte restore only to its exact durable operation owner", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 0})
      assert {:ok, reservation} = reserve(context, "zero-owner", "restore_staging", 0, snapshot)
      restore = insert_running_restore!(context, snapshot, reservation)

      assert {:ok, %{reservation: committed, result: committed_owner}} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 0,
                 fn _reservation ->
                   completed =
                     restore
                     |> ProjectSnapshotRestore.complete_changeset(
                       %{
                         result_digest: String.duplicate("a", 64),
                         restored_asset_count: 0
                       },
                       TimeHelpers.now()
                     )
                     |> Repo.update!()

                   {:ok, completed}
                 end
               )

      assert committed.status == "committed"
      assert committed.actual_bytes == 0
      assert is_nil(committed.storage_started_at)
      assert committed_owner.id == restore.id
      assert committed_owner.status == "completed"
      assert committed_owner.generation == restore.generation + 1
      assert committed_owner.result == %{restored_asset_count: 0}

      usage = Billing.workspace_storage_usage(context.workspace.id)
      assert usage.active_reservations.bytes == 0
      assert usage.current_assets.bytes == 0
    end

    test "database rejects storage-start evidence on a zero-byte export lease", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      assert {:ok, lease} = reserve(context, "db-zero-export", "snapshot_export", 0, snapshot)

      changeset =
        lease
        |> Ecto.Changeset.change(
          storage_started_at: TimeHelpers.now(),
          cleanup_inventory_digest: String.duplicate("a", 64),
          cleanup_inventory_count: 1
        )
        |> Ecto.Changeset.check_constraint(:storage_started_at,
          name: :workspace_storage_reservations_zero_byte_snapshot_export_lease
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{storage_started_at: [_]} = errors_on(rejected)
    end

    test "recovery treats its clock as advisory and revalidates expiry under lock", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      assert {:ok, lease} = reserve(context, "future-advisory", "snapshot_export", 0, snapshot)

      assert %{candidate_count: 1, released_count: 0, failure_count: 0} =
               Versioning.recover_expired_project_snapshot_export_leases(
                 DateTime.add(TimeHelpers.now(), 2 * 24 * 60 * 60, :second)
               )

      assert Repo.get!(StorageReservation, lease.id).status == "active"

      assert %{candidate_count: 0, released_count: 0, changed_count: 0, failure_count: 1} =
               Billing.recover_expired_snapshot_export_leases(TimeHelpers.now(), [1])
    end

    test "retention recovery releases only expired zero-byte export leases", context do
      expired_snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      live_snapshot =
        insert_full_snapshot!(context.project, 2, %{project: 10, metadata: 10, assets: 10})

      positive_snapshot =
        insert_full_snapshot!(context.project, 3, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, expired} =
               reserve(context, "expired-export", "snapshot_export", 0, expired_snapshot)

      assert {:ok, live} =
               reserve(context, "live-export", "snapshot_export", 0, live_snapshot)

      assert {:ok, positive} =
               reserve(context, "positive-export", "snapshot_export", 100, positive_snapshot)

      now = TimeHelpers.now()

      for reservation <- [expired, positive] do
        reservation
        |> Ecto.Changeset.change(
          accounting_measured_at: DateTime.add(now, -120, :second),
          expires_at: DateTime.add(now, -60, :second)
        )
        |> Repo.update!()
      end

      handler_id = "snapshot-export-lease-recovery-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :retention, :stop],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project_snapshots:#{context.project.id}")
      assert :ok = ProjectSnapshotRetentionWorker.perform(%Oban.Job{args: %{}})

      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == expired_snapshot.id

      assert_receive {
        [:storyarn, :snapshot, :retention, :stop],
        %{
          expired_export_lease_candidate_count: 1,
          expired_export_lease_count: 1,
          expired_export_lease_changed_count: 0,
          failure_count: 0
        },
        %{status: :ok}
      }

      assert %StorageReservation{
               status: "released",
               release_reason: "expired_snapshot_export_lease",
               cleanup_status: "not_required",
               storage_started_at: nil
             } = Repo.get!(StorageReservation, expired.id)

      assert Repo.get!(StorageReservation, live.id).status == "active"
      assert Repo.get!(StorageReservation, positive.id).status == "active"

      assert {:ok, %SnapshotCleanupIntent{project_snapshot_id: snapshot_id}} =
               Versioning.delete_project_snapshot(
                 user_scope_fixture(context.user),
                 context.project,
                 expired_snapshot.id
               )

      assert snapshot_id == expired_snapshot.id
    end

    test "retention recovery drains more than one export lease batch with a stable keyset continuation", context do
      snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})

      expired =
        for index <- 1..51 do
          assert {:ok, lease} =
                   reserve(context, "expired-export-batch-#{index}", "snapshot_export", 0, snapshot)

          lease
        end

      assert {:ok, live} = reserve(context, "live-export-after-batch", "snapshot_export", 0, snapshot)
      assert {:ok, positive} = reserve(context, "positive-export-after-batch", "snapshot_export", 100, snapshot)

      now = TimeHelpers.now()
      accounting_measured_at = DateTime.add(now, -120, :second)
      expires_at = DateTime.add(now, -60, :second)
      expired_ids = Enum.map(expired, & &1.id)

      {51, _rows} =
        Repo.update_all(
          from(reservation in StorageReservation, where: reservation.id in ^expired_ids),
          set: [accounting_measured_at: accounting_measured_at, expires_at: expires_at]
        )

      positive
      |> Ecto.Changeset.change(accounting_measured_at: accounting_measured_at, expires_at: expires_at)
      |> Repo.update!()

      assert :ok = ProjectSnapshotRetentionWorker.perform(%Oban.Job{args: %{}})

      first_batch_last_id = expired |> Enum.at(49) |> Map.fetch!(:id)

      assert 50 ==
               Repo.aggregate(
                 from(reservation in StorageReservation,
                   where: reservation.id in ^expired_ids and reservation.status == "released"
                 ),
                 :count
               )

      assert [%Oban.Job{args: continuation_args} = continuation] =
               all_enqueued(worker: ProjectSnapshotRetentionWorker)

      assert continuation_args["export_lease_after_id"] == first_batch_last_id
      assert is_binary(continuation_args["export_lease_cutoff"])

      assert :ok = ProjectSnapshotRetentionWorker.perform(continuation)

      assert 51 ==
               Repo.aggregate(
                 from(reservation in StorageReservation,
                   where: reservation.id in ^expired_ids and reservation.status == "released"
                 ),
                 :count
               )

      assert Repo.get!(StorageReservation, live.id).status == "active"
      assert Repo.get!(StorageReservation, positive.id).status == "active"
    end

    test "purges only retained terminal no-write export lease rows", context do
      old_snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      recent_snapshot = insert_full_snapshot!(context.project, 2, %{project: 10, metadata: 10, assets: 10})
      active_snapshot = insert_full_snapshot!(context.project, 3, %{project: 10, metadata: 10, assets: 10})
      positive_snapshot = insert_full_snapshot!(context.project, 4, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, old} = reserve(context, "old-export-history", "snapshot_export", 0, old_snapshot)
      assert {:ok, recent} = reserve(context, "recent-export-history", "snapshot_export", 0, recent_snapshot)
      assert {:ok, active} = reserve(context, "active-export-history", "snapshot_export", 0, active_snapshot)

      assert {:ok, positive} =
               reserve(context, "positive-export-history", "snapshot_export", 100, positive_snapshot)

      released =
        for lease <- [old, recent, positive] do
          assert {:ok, released} =
                   Billing.release_storage_reservation(
                     lease.id,
                     lease.lease_token,
                     lease.generation,
                     %{
                       reason: "snapshot export finished",
                       cleanup_status: "not_required",
                       cleanup_proof: no_write_proof(lease)
                     }
                   )

          released
        end

      [old_released, recent_released, positive_released] = released
      now = TimeHelpers.now()

      old_released
      |> Ecto.Changeset.change(settled_at: DateTime.add(now, -8 * 24 * 60 * 60, :second))
      |> Repo.update!()

      cutoff = DateTime.add(now, -7 * 24 * 60 * 60, :second)

      assert %{
               candidate_count: 1,
               purged_count: 1,
               changed_count: 0,
               failure_count: 0,
               last_candidate_id: last_candidate_id
             } = Billing.purge_released_snapshot_export_leases(cutoff)

      assert last_candidate_id == old_released.id
      refute Repo.get(StorageReservation, old_released.id)
      assert Repo.get!(StorageReservation, recent_released.id).status == "released"
      assert Repo.get!(StorageReservation, positive_released.id).status == "released"
      assert Repo.get!(StorageReservation, active.id).status == "active"
    end

    test "retains the newest zero-byte export lease as rollback evidence", context do
      first_snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      second_snapshot = insert_full_snapshot!(context.project, 2, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, first} = reserve(context, "first-export-evidence", "snapshot_export", 0, first_snapshot)
      assert {:ok, second} = reserve(context, "second-export-evidence", "snapshot_export", 0, second_snapshot)

      released =
        for lease <- [first, second] do
          assert {:ok, released} =
                   Billing.release_storage_reservation(
                     lease.id,
                     lease.lease_token,
                     lease.generation,
                     %{
                       reason: "snapshot export finished",
                       cleanup_status: "not_required",
                       cleanup_proof: no_write_proof(lease)
                     }
                   )

          released
        end

      [first_released, second_released] = released
      now = TimeHelpers.now()
      settled_at = DateTime.add(now, -8 * 24 * 60 * 60, :second)

      {2, _rows} =
        Repo.update_all(
          from(reservation in StorageReservation,
            where: reservation.id in ^Enum.map(released, & &1.id)
          ),
          set: [settled_at: settled_at]
        )

      assert %{candidate_count: 1, purged_count: 1, changed_count: 0, failure_count: 0} =
               Billing.purge_released_snapshot_export_leases(DateTime.add(now, -7 * 24 * 60 * 60, :second))

      refute Repo.get(StorageReservation, first_released.id)
      assert Repo.get!(StorageReservation, second_released.id).status == "released"
    end

    test "a publication claim prevents terminal export-lease retention from deleting its owner", context do
      claimed_snapshot = insert_full_snapshot!(context.project, 1, %{project: 10, metadata: 10, assets: 10})
      later_snapshot = insert_full_snapshot!(context.project, 2, %{project: 10, metadata: 10, assets: 10})

      assert {:ok, claimed} = reserve(context, "claimed-export-history", "snapshot_export", 0, claimed_snapshot)

      assert {:ok, claimed} =
               Billing.release_storage_reservation(
                 claimed.id,
                 claimed.lease_token,
                 claimed.generation,
                 %{
                   reason: "snapshot export finished",
                   cleanup_status: "not_required",
                   cleanup_proof: no_write_proof(claimed)
                 }
               )

      now = TimeHelpers.now()

      claimed
      |> Ecto.Changeset.change(settled_at: DateTime.add(now, -8 * 24 * 60 * 60, :second))
      |> Repo.update!()

      Repo.insert!(%SnapshotObjectPublicationClaim{
        object_prefix: claimed_snapshot.object_prefix,
        claim_token: Ecto.UUID.generate(),
        inventory_digest: SnapshotObjectPublicationClaim.inventory_digest(claimed_snapshot),
        storage_reservation_id_snapshot: claimed.id,
        storage_reservation_lease_token: claimed.lease_token,
        status: "poisoned",
        lease_expires_at: nil,
        inserted_at: now,
        updated_at: now
      })

      # A later zero-byte row makes the claimed lease independently eligible
      # from the newest-evidence guard, so this exercises the claim fence.
      assert {:ok, _later} =
               reserve(context, "later-export-evidence", "snapshot_export", 0, later_snapshot)

      assert %{candidate_count: 1, purged_count: 0, changed_count: 1, failure_count: 0} =
               Billing.purge_released_snapshot_export_leases(DateTime.add(now, -7 * 24 * 60 * 60, :second))

      assert Repo.get!(StorageReservation, claimed.id).status == "released"
    end
  end

  defp insert_running_restore!(context, snapshot, reservation) do
    now = TimeHelpers.now()

    Repo.insert!(%ProjectSnapshotRestore{
      workspace_id: context.workspace.id,
      project_id: context.project.id,
      project_snapshot_id: snapshot.id,
      requested_by_id: context.user.id,
      idempotency_key: Ecto.UUID.generate(),
      status: "running",
      phase: "materializing",
      generation: 2,
      attempt: 1,
      storage_reservation_id: reservation.id,
      storage_reservation_generation: reservation.generation,
      storage_reservation_lease_token: reservation.lease_token,
      snapshot_lifecycle_generation: snapshot.lifecycle_generation,
      snapshot_accounting_generation: snapshot.accounting_generation,
      archive_storage_key: snapshot.archive_storage_key,
      archive_size_bytes: snapshot.archive_size_bytes,
      archive_checksum: snapshot.archive_checksum,
      manifest_storage_key: snapshot.manifest_storage_key,
      manifest_size_bytes: snapshot.manifest_size_bytes,
      manifest_checksum: snapshot.manifest_checksum,
      failure_details: %{},
      result: %{},
      requested_at: now,
      claimed_at: now,
      state_updated_at: now,
      inserted_at: now,
      updated_at: now
    })
  end

  defp reserve(context, key, kind, bytes, snapshot) do
    Billing.reserve_storage(reservation_attrs(context, key, kind, bytes, snapshot))
  end

  defp insert_cleanup_scope!(reservation, relative_paths \\ ["snapshot.zip", "manifest.json"]) do
    assert {:ok, prefixes} = StorageAccounting.operation_object_prefixes(reservation)
    mark_reservation_started!(reservation, relative_paths)

    if reservation.kind == "snapshot_build" do
      insert_publication_claim!(reservation, "poisoned")
    end

    {storage_keys, cleanup_scope} = cleanup_inventory(prefixes, relative_paths)

    cleanup_request = Repo.insert!(%StorageCleanupRequest{storage_keys: storage_keys})
    cleanup_scope = Map.put(cleanup_scope, :cleanup_request_id, cleanup_request.id)

    {cleanup_request, cleanup_scope}
  end

  defp mark_reservation_started!(reservation, relative_paths \\ ["snapshot.zip", "manifest.json"]) do
    assert {:ok, prefixes} = StorageAccounting.operation_object_prefixes(reservation)
    {storage_keys, cleanup_plan} = cleanup_inventory(prefixes, relative_paths)
    cleanup_plan = Map.put(cleanup_plan, :storage_keys, storage_keys)

    assert {:ok, marked} =
             Billing.mark_storage_reservation_started(
               reservation.id,
               reservation.lease_token,
               reservation.generation,
               cleanup_plan
             )

    marked
  end

  defp cleanup_inventory(%{staging: staging, ready: ready}, relative_paths) do
    storage_keys = for prefix <- [staging, ready], path <- relative_paths, do: prefix <> "/" <> path

    {storage_keys,
     %{
       staging_prefix: staging,
       ready_prefix: ready,
       storage_keys: storage_keys
     }}
  end

  defp cleanup_inventory(%{temporary: temporary}, relative_paths) do
    storage_keys = Enum.map(relative_paths, &(temporary <> "/" <> &1))
    {storage_keys, %{temporary_prefix: temporary, storage_keys: storage_keys}}
  end

  defp prepare_build_publication!(reservation, inventory_source \\ nil) do
    mark_reservation_started!(reservation)
    insert_publication_claim!(reservation, "published", inventory_source)
  end

  defp insert_publication_claim!(reservation, status, inventory_source \\ nil) do
    lease_expires_at = if status in ["staging", "publishing"], do: DateTime.add(TimeHelpers.now(), 3600, :second)
    inventory_source = inventory_source || Repo.get!(ProjectSnapshot, reservation.project_snapshot_id_snapshot)
    inventory_digest = SnapshotObjectPublicationClaim.inventory_digest(inventory_source)

    case Repo.get(SnapshotObjectPublicationClaim, reservation.cleanup_object_prefix) do
      nil ->
        Repo.insert!(%SnapshotObjectPublicationClaim{
          object_prefix: reservation.cleanup_object_prefix,
          claim_token: Ecto.UUID.generate(),
          inventory_digest: inventory_digest,
          storage_reservation_id_snapshot: reservation.id,
          storage_reservation_lease_token: reservation.lease_token,
          status: status,
          lease_expires_at: lease_expires_at,
          inserted_at: TimeHelpers.now(),
          updated_at: TimeHelpers.now()
        })

      %SnapshotObjectPublicationClaim{} = claim ->
        claim
        |> SnapshotObjectPublicationClaim.status_changeset(status, lease_expires_at)
        |> Repo.update!()
    end
  end

  defp no_write_proof(reservation) do
    %{
      type: "storage_not_started",
      storage_namespace: reservation.storage_namespace
    }
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp reservation_attrs(context, key, kind, bytes, snapshot) do
    %{
      workspace_id: context.workspace.id,
      project_id: context.project.id,
      project_snapshot_id: snapshot.id,
      idempotency_key: "#{key}:#{context.project.id}",
      kind: kind,
      reserved_bytes: bytes
    }
  end

  defp insert_asset_row!(context, size) do
    %Asset{}
    |> Ecto.Changeset.change(%{
      filename: "capacity.bin",
      content_type: "application/octet-stream",
      size: size,
      key: "projects/#{context.project.id}/assets/#{Ecto.UUID.generate()}/capacity.bin",
      project_id: context.project.id,
      uploaded_by_id: context.user.id
    })
    |> Repo.insert!()
  end

  defp insert_pending_snapshot!(project, version, sizes \\ %{project: 100, metadata: 50, assets: 0}) do
    blob_count = if sizes.assets > 0, do: 1, else: 0
    archive_size = sizes.project + sizes.assets
    total = archive_size + sizes.metadata

    pending_project_snapshot_fixture(project, %{
      version_number: version,
      archive_size_bytes: archive_size,
      project_size_bytes: sizes.project,
      manifest_size_bytes: sizes.metadata,
      total_size_bytes: total,
      object_count: 2,
      asset_count: blob_count,
      blob_count: blob_count,
      progress_total_bytes: total
    })
  end

  defp finalize_pending_full_snapshot!(snapshot, sizes) do
    snapshot = transition_pending_snapshot_to_verifying!(snapshot)

    {:ok, finalized} =
      Versioning.finalize_project_snapshot_object_set(
        snapshot.id,
        0,
        full_snapshot_object_set_attrs(snapshot, sizes)
      )

    finalized
  end

  defp transition_pending_snapshot_to_verifying!(snapshot) do
    now = TimeHelpers.now()

    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      lifecycle_state: "building",
      progress_phase: "copying",
      building_started_at: now,
      state_updated_at: now
    })
    |> Repo.update!()
    |> ProjectSnapshot.build_state_changeset(%{
      lifecycle_state: "verifying",
      progress_phase: "verifying",
      verifying_started_at: now,
      state_updated_at: now
    })
    |> Repo.update!()
  end

  defp full_snapshot_object_set_attrs(snapshot, sizes) do
    archive_size = sizes.project + sizes.assets
    total = archive_size + sizes.metadata
    now = TimeHelpers.now()

    %{
      expected_lifecycle_generation: snapshot.lifecycle_generation,
      project_id: snapshot.project_id,
      version_number: snapshot.version_number,
      archive_storage_key: snapshot.object_prefix <> "/snapshot.zip",
      archive_size_bytes: archive_size,
      archive_checksum: String.duplicate("d", 64),
      capture_digest: snapshot.capture_digest,
      project_size_bytes: sizes.project,
      project_checksum: @checksum,
      format_version: 2,
      object_prefix: snapshot.object_prefix,
      manifest_storage_key: snapshot.object_prefix <> "/manifest.json",
      manifest_size_bytes: sizes.metadata,
      manifest_checksum: String.duplicate("b", 64),
      total_size_bytes: total,
      accounted_size_bytes: total,
      asset_blob_size_bytes: sizes.assets,
      accounting_version: 1,
      object_count: 2,
      asset_count: 1,
      blob_count: 1,
      mode: "full",
      lifecycle_state: "ready",
      integrity_state: "verified",
      progress_phase: "complete",
      progress_bytes: total,
      progress_total_bytes: total,
      building_started_at: now,
      verifying_started_at: now,
      ready_at: now,
      state_updated_at: now
    }
  end

  defp insert_full_snapshot!(project, version, sizes, asset_count \\ 1, blob_count \\ 1) do
    full_project_snapshot_fixture(project, %{
      version_number: version,
      archive_size_bytes: sizes.project + sizes.assets,
      project_size_bytes: sizes.project,
      manifest_size_bytes: sizes.metadata,
      asset_blob_size_bytes: sizes.assets,
      asset_count: asset_count,
      blob_count: blob_count
    })
  end
end
