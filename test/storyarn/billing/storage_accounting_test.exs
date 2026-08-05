defmodule Storyarn.Billing.StorageAccountingTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageAccounting
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim

  @checksum String.duplicate("a", 64)

  setup do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)

    %{user: user, project: project, workspace: project.workspace}
  end

  describe "authoritative usage projection" do
    test "sums mutually exclusive logical assets, snapshot modes, and active reservations", context do
      asset_fixture(context.project, context.user, %{size: 2_000})

      full_snapshot =
        insert_full_snapshot!(context.project, 1, %{project: 100, metadata: 20, assets: 50})

      insert_linked_snapshot!(context.project, 2, %{project: 80, metadata: 20})

      assert {:ok, reservation} =
               reserve(context, "restore", "restore_staging", 30, full_snapshot)

      usage = Billing.workspace_storage_usage(context.workspace.id)

      assert usage.current_assets == %{bytes: 2_000, count: 1}
      assert usage.asset_trash == %{bytes: 0, count: 0}
      assert usage.full_snapshots == %{bytes: 170, count: 1}
      assert usage.linked_snapshots == %{bytes: 100, count: 1}
      assert usage.active_reservations.bytes == 30
      assert usage.active_reservations.by_kind == %{"restore_staging" => 30}
      assert usage.accounted_bytes == 2_300

      assert {:ok, _released} =
               Billing.release_storage_reservation(reservation.id, reservation.lease_token, reservation.generation, %{
                 reason: "restore cancelled before staging",
                 cleanup_status: "not_required",
                 cleanup_proof: no_write_proof(reservation)
               })

      assert Billing.workspace_storage_usage(context.workspace.id).accounted_bytes == 2_270
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
      |> Ecto.Changeset.change(lifecycle_state: "deleting")
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
               snapshot.id => %{active_bytes: 100, export_bytes: 100}
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

    test "allows only one active build or conversion reservation per snapshot", context do
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

      linked_snapshot =
        insert_linked_snapshot!(context.project, 3, %{project: 80, metadata: 20})

      assert {:ok, conversion} =
               reserve(
                 context,
                 "exclusive-conversion",
                 "linked_to_full_conversion",
                 50,
                 linked_snapshot
               )

      assert {:error, :storage_reservation_active_for_snapshot} =
               reserve(
                 context,
                 "competing-conversion",
                 "linked_to_full_conversion",
                 50,
                 linked_snapshot
               )

      assert conversion.status == "active"
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

    test "a linked-to-full conversion reserves and commits only its added blob bytes", context do
      linked_snapshot =
        insert_linked_snapshot!(context.project, 1, %{project: 80, metadata: 20})

      assert {:ok, reservation} =
               reserve(
                 context,
                 "linked-conversion",
                 "linked_to_full_conversion",
                 50,
                 linked_snapshot
               )

      mark_reservation_started!(reservation)

      usage_while_active = Billing.workspace_storage_usage(context.workspace.id)
      assert usage_while_active.linked_snapshots == %{bytes: 100, count: 1}
      assert usage_while_active.active_reservations.bytes == 50
      assert usage_while_active.accounted_bytes == 150

      assert {:ok, %{result: converted, reservation: committed}} =
               Billing.commit_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 50,
                 fn locked_reservation ->
                   {:ok,
                    convert_linked_to_full!(
                      linked_snapshot,
                      50,
                      locked_reservation.cleanup_object_prefix
                    )}
                 end
               )

      assert converted.id == linked_snapshot.id
      assert converted.mode == "full"
      assert converted.accounted_size_bytes == 150
      assert converted.asset_blob_size_bytes == 50
      assert committed.actual_bytes == 50

      usage = Billing.workspace_storage_usage(context.workspace.id)
      assert usage.active_reservations.bytes == 0
      assert usage.linked_snapshots == %{bytes: 0, count: 0}
      assert usage.full_snapshots == %{bytes: 150, count: 1}
      assert usage.accounted_bytes == 150
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

    test "owned cleanup accepts only canonical keys in the build's exact object-set namespaces", context do
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
            "projects/#{context.project.id}/snapshots/object-sets/v1/ready/AAAAAAAAAAAAAAAA/project.json"
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
        insert_cleanup_scope!(reservation, [
          "project.json",
          "manifest.json",
          "blobs/#{@checksum}.bin"
        ])

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

  defp reserve(context, key, kind, bytes, snapshot) do
    Billing.reserve_storage(reservation_attrs(context, key, kind, bytes, snapshot))
  end

  defp insert_cleanup_scope!(reservation, relative_paths \\ ["project.json", "manifest.json"]) do
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

  defp mark_reservation_started!(reservation, relative_paths \\ ["project.json", "manifest.json"]) do
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

  defp cleanup_inventory(%{temporary: temporary, ready: ready}, relative_paths) do
    storage_keys = for prefix <- [temporary, ready], path <- relative_paths, do: prefix <> "/" <> path

    {storage_keys,
     %{
       temporary_prefix: temporary,
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

  defp reservation_attrs(context, key, kind, bytes, snapshot) do
    attrs = %{
      workspace_id: context.workspace.id,
      project_id: context.project.id,
      project_snapshot_id: snapshot.id,
      idempotency_key: "#{key}:#{context.project.id}",
      kind: kind,
      reserved_bytes: bytes
    }

    if kind == "linked_to_full_conversion" do
      token = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      Map.put(attrs, :ready_object_prefix, "projects/#{context.project.id}/snapshots/object-sets/v1/ready/#{token}")
    else
      attrs
    end
  end

  defp insert_asset_row!(context, size) do
    %Storyarn.Assets.Asset{}
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
    total = sizes.project + sizes.metadata + sizes.assets

    pending_project_snapshot_fixture(project, %{
      version_number: version,
      project_size_bytes: sizes.project,
      manifest_size_bytes: sizes.metadata,
      total_size_bytes: total,
      object_count: blob_count + 2,
      asset_count: blob_count,
      blob_count: blob_count,
      progress_total_bytes: total
    })
  end

  defp finalize_pending_full_snapshot!(snapshot, sizes) do
    {:ok, finalized} =
      Versioning.finalize_project_snapshot_object_set(
        snapshot.id,
        0,
        full_snapshot_object_set_attrs(snapshot, sizes)
      )

    finalized
  end

  defp full_snapshot_object_set_attrs(snapshot, sizes) do
    total = sizes.project + sizes.metadata + sizes.assets
    now = TimeHelpers.now()

    %{
      project_id: snapshot.project_id,
      version_number: snapshot.version_number,
      project_storage_key: snapshot.object_prefix <> "/project.json",
      project_size_bytes: sizes.project,
      project_checksum: @checksum,
      format_version: 1,
      object_prefix: snapshot.object_prefix,
      manifest_storage_key: snapshot.object_prefix <> "/manifest.json",
      manifest_size_bytes: sizes.metadata,
      manifest_checksum: String.duplicate("b", 64),
      total_size_bytes: total,
      accounted_size_bytes: total,
      asset_blob_size_bytes: sizes.assets,
      accounting_version: 1,
      object_count: 3,
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

  defp convert_linked_to_full!(snapshot, added_asset_bytes, prefix) do
    total = snapshot.accounted_size_bytes + added_asset_bytes

    {:ok, converted} =
      Versioning.convert_linked_project_snapshot_object_set(
        snapshot.id,
        snapshot.accounting_generation,
        %{
          project_id: snapshot.project_id,
          version_number: snapshot.version_number,
          project_storage_key: prefix <> "/project.json",
          project_size_bytes: snapshot.project_size_bytes,
          project_checksum: snapshot.project_checksum,
          format_version: 1,
          object_prefix: prefix,
          manifest_storage_key: prefix <> "/manifest.json",
          manifest_size_bytes: snapshot.manifest_size_bytes,
          manifest_checksum: snapshot.manifest_checksum,
          total_size_bytes: total,
          object_count: 3,
          asset_count: snapshot.asset_count,
          blob_count: 1,
          mode: "full"
        }
      )

    converted
  end

  defp insert_full_snapshot!(project, version, sizes, asset_count \\ 1, blob_count \\ 1) do
    full_project_snapshot_fixture(project, %{
      version_number: version,
      project_size_bytes: sizes.project,
      manifest_size_bytes: sizes.metadata,
      asset_blob_size_bytes: sizes.assets,
      asset_count: asset_count,
      blob_count: blob_count
    })
  end

  defp insert_linked_snapshot!(project, version, sizes) do
    total = sizes.project + sizes.metadata
    token = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/#{token}"
    now = TimeHelpers.now()

    %ProjectSnapshot{}
    |> Ecto.Changeset.change(%{
      project_id: project.id,
      version_number: version,
      project_storage_key: prefix <> "/project.json",
      project_size_bytes: sizes.project,
      project_checksum: @checksum,
      format_version: 1,
      object_prefix: prefix,
      manifest_storage_key: prefix <> "/manifest.json",
      manifest_size_bytes: sizes.metadata,
      manifest_checksum: String.duplicate("c", 64),
      total_size_bytes: total,
      object_count: 2,
      asset_count: 2,
      blob_count: 0,
      mode: "linked",
      lifecycle_state: "ready",
      integrity_state: "verified",
      accounted_size_bytes: total,
      asset_blob_size_bytes: 0,
      accounting_version: 1,
      accounting_generation: 1,
      accounting_measured_at: now,
      idempotency_key: Ecto.UUID.generate(),
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: String.duplicate("d", 64),
      captured_at: now,
      progress_phase: "complete",
      progress_bytes: total,
      progress_total_bytes: total,
      build_attempt: 1,
      building_started_at: now,
      verifying_started_at: now,
      ready_at: now,
      state_updated_at: now
    })
    |> Repo.insert!()
  end
end
