defmodule Storyarn.Versioning.ProjectSnapshotBuildTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.Storage.Local
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageAccounting
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Notifications
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Sheet
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotBuild
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.RetryStorageCleanupRequestsWorker

  describe "request_full_project_snapshot/3" do
    test "normalizes inserted lifecycle time to the database clock" do
      project = project_fixture(user_fixture())
      database_before = database_clock_now()
      future = DateTime.add(database_before, 300, :second)
      snapshot = pending_project_snapshot_fixture(project, %{state_updated_at: future})

      database_after = database_clock_now()
      assert DateTime.compare(snapshot.state_updated_at, database_before) in [:eq, :gt]
      assert DateTime.compare(snapshot.state_updated_at, database_after) in [:eq, :lt]
    end

    test "atomically queues a minimal lease and materializes exact capture in the worker" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      asset = upload_asset!(project, user, "capture bytes")
      flow = flow_fixture(project)
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      _spanish = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Archived source", "responses" => []}})

      archived_text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

      assert {:ok, archived_text} =
               Localization.update_text(archived_text, %{
                 translated_text: "Archived translation",
                 status: "final"
               })

      assert {1, nil} =
               Repo.update_all(
                 from(current in FlowNode, where: current.id == ^node.id),
                 set: [deleted_at: TimeHelpers.now()]
               )

      idempotency_key = Ecto.UUID.generate()

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(scope, project, %{
                 idempotency_key: idempotency_key,
                 title: "Milestone"
               })

      assert snapshot.lifecycle_state == "pending"
      assert snapshot.mode == "full"
      assert snapshot.idempotency_key == idempotency_key
      assert snapshot.format_version == 2
      assert is_nil(snapshot.asset_count)
      assert is_nil(snapshot.blob_count)
      assert is_nil(snapshot.object_count)
      assert snapshot.archive_storage_key == snapshot.object_prefix <> "/snapshot.zip"
      assert snapshot.manifest_storage_key == snapshot.object_prefix <> "/manifest.json"
      assert is_nil(snapshot.archive_size_bytes)
      assert is_nil(snapshot.project_size_bytes)
      assert is_nil(snapshot.capture_digest)
      assert is_nil(snapshot.restore_contract_version)
      assert is_nil(snapshot.captured_at)
      assert is_nil(snapshot.total_size_bytes)
      assert snapshot.progress_bytes == 0
      assert snapshot.progress_total_bytes == 0
      assert is_integer(snapshot.storage_reservation_id)
      assert is_integer(snapshot.build_job_id)
      refute Repo.get(ProjectSnapshotCapture, snapshot.id)

      reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
      assert reservation.status == "active"
      assert reservation.kind == "snapshot_build"
      assert reservation.reserved_bytes == 1

      job = Repo.get!(Oban.Job, snapshot.build_job_id)
      assert job.queue == "snapshot_archives"
      assert job.args == %{"snapshot_id" => snapshot.id}
      assert job.max_attempts == 3

      assert {:ok, replayed} =
               Versioning.request_full_project_snapshot(scope, project, %{
                 idempotency_key: idempotency_key,
                 title: "Ignored replay title"
               })

      assert replayed.id == snapshot.id

      assert Repo.aggregate(
               from(snapshot in ProjectSnapshot, where: snapshot.project_id == ^project.id),
               :count
             ) == 1

      assert Repo.aggregate(
               from(job in Oban.Job,
                 where:
                   job.worker == ^inspect(BuildProjectSnapshotWorker) and
                     fragment("?->>'snapshot_id'", job.args) == ^to_string(snapshot.id)
               ),
               :count,
               :id
             ) == 1

      captured = materialize_snapshot_capture!(snapshot)
      capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)

      assert captured.asset_count == 1
      assert captured.blob_count == 1
      assert captured.object_count == 2
      assert captured.archive_size_bytes > 0
      assert captured.total_size_bytes == captured.archive_size_bytes + captured.manifest_size_bytes
      assert captured.progress_total_bytes == captured.total_size_bytes
      assert captured.restore_contract_version == 1
      assert capture.capture_boundary == captured.capture_boundary
      assert capture.capture_digest == captured.capture_digest
      assert byte_size(capture.project_json) == captured.project_size_bytes
      assert byte_size(capture.manifest_json) == captured.manifest_size_bytes
      assert map_size(capture.source_keys) == 1
      assert capture.object_count == 3

      assert capture.total_size_bytes ==
               capture.project_size_bytes + capture.manifest_size_bytes + capture.asset_blob_size_bytes

      project_object = Jason.decode!(capture.project_json)
      assert project_object["project"]["name"] == project.name

      assert Enum.map(project_object["localization"]["languages"], & &1["locale_code"]) == ["en", "es"]

      captured_text =
        Enum.find(project_object["localization"]["texts"], fn row ->
          row["source_type"] == archived_text.source_type and
            row["source_id"] == archived_text.source_id and
            row["source_field"] == archived_text.source_field and
            row["locale_code"] == archived_text.locale_code
        end)

      assert captured_text == localized_text_snapshot(archived_text)

      assert project_object["asset_catalog_refs"] == %{
               to_string(asset.id) => "asset-000001"
             }

      blob_key = protected_blob_key(project.id, asset)
      assert Map.values(capture.source_keys) == [blob_key]

      extended = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
      assert extended.status == "active"
      assert extended.reserved_bytes == captured.total_size_bytes
      assert extended.generation == reservation.generation + 2
    end

    test "wakes the snapshot queue after commit for new requests and idempotent replays" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      idempotency_key = Ecto.UUID.generate()
      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      parent = self()

      notifier = fn payload ->
        in_transaction? = Repo.in_transaction?()

        visibility =
          fn ->
            snapshot =
              Repo.get_by!(ProjectSnapshot,
                project_id: project.id,
                idempotency_key: idempotency_key
              )

            reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
            job = Repo.get!(Oban.Job, snapshot.build_job_id)
            {snapshot.id, reservation.status, job.state, job.args}
          end
          |> Task.async()
          |> Task.await()

        send(parent, {:snapshot_queue_wakeup, payload, in_transaction?, visibility})
        :ok
      end

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :queue_notifier, notifier)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      attrs = %{idempotency_key: idempotency_key, title: "Durable wake"}
      assert {:ok, snapshot} = Versioning.request_full_project_snapshot(scope, project, attrs)

      assert_receive {:snapshot_queue_wakeup, %{queue: "snapshot_archives"}, false,
                      {snapshot_id, "active", "available", %{"snapshot_id" => job_snapshot_id}}}

      assert snapshot_id == snapshot.id
      assert job_snapshot_id == snapshot.id

      assert {:ok, replayed} =
               Versioning.request_full_project_snapshot(scope, project, %{attrs | title: "Ignored replay"})

      assert replayed.id == snapshot.id

      assert_receive {:snapshot_queue_wakeup, %{queue: "snapshot_archives"}, false,
                      {^snapshot_id, "active", "available", %{"snapshot_id" => ^snapshot_id}}}
    end

    test "a post-commit queue wake failure never invalidates the durable snapshot job" do
      user = user_fixture()
      project = project_fixture(user)
      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :queue_notifier, fn _payload ->
          raise "private notifier failure"
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      assert {:ok, snapshot} = request_snapshot(user, project)
      assert Repo.get!(ProjectSnapshot, snapshot.id).lifecycle_state == "pending"

      assert %Oban.Job{state: "available", args: %{"snapshot_id" => snapshot_id}} =
               Repo.get!(Oban.Job, snapshot.build_job_id)

      assert snapshot_id == snapshot.id
      assert Repo.get!(StorageReservation, snapshot.storage_reservation_id).status == "active"
    end

    test "reports durable retry timing and a safe generic error without exposing Oban details" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} = request_snapshot(user, project)

      initial = ProjectSnapshotBuild.build_statuses([snapshot])[snapshot.id]
      assert initial.job_state == "available"
      assert initial.attempt == 0
      assert initial.max_attempts == 3
      refute initial.retrying
      assert is_nil(initial.next_retry_at)
      assert is_nil(initial.retry_error_code)

      scheduled_at =
        TimeHelpers.now()
        |> DateTime.add(600, :second)
        |> Map.put(:microsecond, {0, 6})

      snapshot.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "retryable",
        attempt: 2,
        scheduled_at: scheduled_at,
        errors: [
          %{
            "attempt" => 1,
            "at" => DateTime.to_iso8601(TimeHelpers.now()),
            "error" => "first private provider failure"
          },
          %{
            "attempt" => 2,
            "at" => DateTime.to_iso8601(TimeHelpers.now()),
            "error" => "provider secret and stacktrace must never reach the client"
          }
        ]
      )
      |> Repo.update!()

      retrying = ProjectSnapshotBuild.build_statuses([snapshot])[snapshot.id]

      assert retrying == %{
               job_state: "retryable",
               attempt: 2,
               max_attempts: 3,
               retrying: true,
               next_retry_at: scheduled_at,
               retry_error_code: "build_failed"
             }

      refute inspect(retrying) =~ "provider secret"
      refute inspect(retrying) =~ "stacktrace"
    end

    test "terminalizes an exact capture that exceeds workspace storage without retrying" do
      user = user_fixture()
      workspace = Storyarn.WorkspacesFixtures.workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      capacity_project = project_fixture(user, %{workspace: workspace})
      scope = user_scope_fixture(user)
      storage_limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)

      %Asset{}
      |> Ecto.Changeset.change(%{
        filename: "workspace-capacity.bin",
        content_type: "application/octet-stream",
        size: storage_limit - 1,
        key: "projects/#{capacity_project.id}/assets/workspace-capacity.bin",
        url: "https://example.com/workspace-capacity.bin",
        project_id: capacity_project.id,
        uploaded_by_id: user.id
      })
      |> Repo.insert!()

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project, %{title: "Too large"})
      job = requested_job(requested)
      assert BuildProjectSnapshotWorker.canonical_attempt(job) == 1

      assert {:discard, :storage_limit_reached} = BuildProjectSnapshotWorker.perform(job)
      assert_receive :notifications_changed
      refute_receive :notifications_changed

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.progress_phase == "failed"
      assert failed.failure_code == "storage_limit_reached"
      assert failed.failure_message == "The workspace no longer has enough storage for this snapshot."
      refute Repo.get(ProjectSnapshotCapture, failed.id)

      assert %StorageReservation{status: "released", release_reason: "storage_limit_reached"} =
               Repo.get!(StorageReservation, requested.storage_reservation_id)

      assert Repo.aggregate(
               from(reservation in StorageReservation,
                 where: reservation.project_snapshot_id_snapshot == ^requested.id
               ),
               :count
             ) == 1

      status = ProjectSnapshotBuild.build_statuses([failed])[failed.id]
      refute status.retrying
      assert is_nil(status.next_retry_at)
      assert is_nil(status.retry_error_code)
      assert_snapshot_notification(scope, failed, "failure", "Too large")

      assert :ok = BuildProjectSnapshotWorker.perform(job)
      refute_receive :notifications_changed
      assert_snapshot_notification(scope, failed, "failure", "Too large")
    end

    test "terminalizes a snapshot on the third logical capture failure" do
      user = user_fixture()
      project = project_fixture(user)
      _asset = upload_asset!(project, user, "capture retry budget")

      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      assert job.max_attempts == 3

      original_storage_config = Application.get_env(:storyarn, :storage, [])
      {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})
      SnapshotReadSwitchStorage.set_stat_result({:error, {:storage_timeout, "private provider details"}})

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :adapter, SnapshotReadSwitchStorage)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, :storage, original_storage_config)

        if Process.whereis(SnapshotReadSwitchStorage) do
          Agent.stop(SnapshotReadSwitchStorage)
        end
      end)

      assert {:error, :build_failed} =
               job
               |> Map.put(:errors, [])
               |> BuildProjectSnapshotWorker.perform()

      assert %ProjectSnapshot{lifecycle_state: "pending", failure_code: nil} =
               Repo.get!(ProjectSnapshot, requested.id)

      assert {:error, :build_failed} =
               job
               |> Map.put(:errors, [%{"attempt" => 1}])
               |> BuildProjectSnapshotWorker.perform()

      assert %ProjectSnapshot{lifecycle_state: "pending", failure_code: nil} =
               Repo.get!(ProjectSnapshot, requested.id)

      assert {:discard, :build_failed} =
               job
               |> Map.put(:errors, [%{"attempt" => 1}, %{"attempt" => 2}])
               |> BuildProjectSnapshotWorker.perform()

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.failure_code == "build_failed"

      assert failed.failure_message ==
               "The snapshot could not be created."

      refute failed.failure_message =~ "private provider details"
      assert Repo.get!(StorageReservation, failed.storage_reservation_id).status == "released"
      refute Repo.get(ProjectSnapshotCapture, failed.id)
    end

    test "rejects callers without project management permission before capture" do
      owner = user_fixture()
      unauthorized_user = user_fixture()
      project = project_fixture(owner)

      assert {:error, :unauthorized} =
               Versioning.request_full_project_snapshot(
                 user_scope_fixture(unauthorized_user),
                 project,
                 %{idempotency_key: Ecto.UUID.generate()}
               )

      refute Repo.exists?(from(snapshot in ProjectSnapshot, where: snapshot.project_id == ^project.id))
    end

    test "database rejects mutation of immutable capture bytes" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      snapshot = materialize_snapshot_capture!(snapshot)
      capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)

      assert_raise Postgrex.Error, ~r/project snapshot captures are immutable/, fn ->
        capture
        |> Ecto.Changeset.change(project_json: ~s({"tampered":true}))
        |> Repo.update!()
      end
    end

    test "database rejects mutation of snapshot capture identity" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      snapshot = materialize_snapshot_capture!(snapshot)

      assert_raise Postgrex.Error, ~r/project snapshot capture identity is immutable/, fn ->
        snapshot
        |> Ecto.Changeset.change(capture_digest: String.duplicate("f", 64))
        |> Repo.update!()
      end
    end

    test "canonical capture preserves active localization outside source and locale inventories" do
      user = user_fixture()
      project = project_fixture(user)
      _active_locale = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      archived_locale = language_fixture(project, %{locale_code: "fr", name: "French"})
      assert {:ok, _archived_locale} = Localization.remove_language(archived_locale)

      flow = flow_fixture(project)
      deleted_node = node_fixture(flow)
      assert {:ok, _deleted_node, _meta} = Storyarn.Flows.delete_node(deleted_node)
      wrong_type_sheet = sheet_without_flow_node_id(project)

      base_id = 1_000_000_000 + rem(project.id, 10_000_000) * 10

      drift_rows = [
        localized_text_fixture(project.id, %{
          source_id: wrong_type_sheet.id,
          locale_code: "es",
          source_text: "Wrong table source",
          source_text_hash: "wrong-table-source-hash",
          translated_source_hash: "wrong-table-translation-hash",
          translated_text: "Wrong table translation",
          status: "draft",
          word_count: 3
        }),
        localized_text_fixture(project.id, %{
          source_id: deleted_node.id,
          locale_code: "fr",
          source_text: "Deleted source",
          source_text_hash: "deleted-source-hash",
          translated_source_hash: "deleted-translation-hash",
          translated_text: "Deleted translation",
          status: "review",
          word_count: 2
        }),
        localized_text_fixture(project.id, %{
          source_type: "block",
          source_id: base_id + 1,
          locale_code: "zz",
          source_text: "Dangling source",
          source_text_hash: "dangling-source-hash",
          translated_source_hash: "dangling-translation-hash",
          translated_text: "Dangling translation",
          status: "in_progress",
          word_count: 2,
          machine_translated: true
        })
      ]

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)
      captured_texts = project_json["localization"]["texts"]

      captured_by_key =
        Map.new(captured_texts, fn row ->
          {{row["source_type"], row["source_id"], row["source_field"], row["locale_code"]}, row}
        end)

      Enum.each(drift_rows, fn row ->
        key = {row.source_type, row.source_id, row.source_field, row.locale_code}
        assert captured_by_key[key] == localized_text_snapshot(row)
      end)

      active_inventory = Localization.list_texts_for_canonical_snapshot(project.id)
      assert length(captured_texts) == length(active_inventory)
      assert project_json["entity_counts"]["localized_texts"] == length(active_inventory)
    end

    test "captures missing speaker drift without mutating raw content" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      speaker = Storyarn.SheetsFixtures.sheet_fixture(project, %{name: "Legacy speaker"})
      flow = flow_fixture(project)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Production line",
            "stage_directions" => "Quietly",
            "responses" => []
          }
        })

      dialogue_text =
        "flow_node"
        |> Localization.get_texts_for_source(dialogue.id)
        |> Enum.find(&(&1.source_field == "text"))

      Repo.update_all(
        from(row in LocalizedText, where: row.id == ^dialogue_text.id),
        set: [speaker_sheet_id: nil]
      )

      assert {:ok, trashed_speaker} = Storyarn.Sheets.trash_sheet(speaker)
      assert trashed_speaker.deleted_at

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)

      flow_snapshot =
        project_json["flows"]
        |> Enum.find(&(&1["id"] == flow.id))
        |> Map.fetch!("snapshot")

      captured_dialogue = Enum.find(flow_snapshot["nodes"], &(&1["original_id"] == dialogue.id))
      assert captured_dialogue["data"]["speaker_sheet_id"] == speaker.id

      captured_text =
        Enum.find(flow_snapshot["localization"], fn row ->
          row["source_id"] == dialogue.id and row["source_field"] == "text"
        end)

      assert captured_text["speaker_sheet_id"] == nil
      assert Repo.get!(FlowNode, dialogue.id).data["speaker_sheet_id"] == speaker.id

      assert Repo.get!(LocalizedText, dialogue_text.id).speaker_sheet_id ==
               nil

      assert Repo.get!(Sheet, speaker.id).deleted_at
    end

    test "captures malformed raw flow data without blocking the snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Initially valid", "responses" => []}
        })

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [data: Map.put(dialogue.data, "text", 123)]
      )

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)

      flow_snapshot =
        project_json["flows"]
        |> Enum.find(&(&1["id"] == flow.id))
        |> Map.fetch!("snapshot")

      captured_dialogue = Enum.find(flow_snapshot["nodes"], &(&1["original_id"] == dialogue.id))

      assert captured_dialogue["data"]["text"] == 123
      assert Repo.get!(FlowNode, dialogue.id).data["text"] == 123
    end

    test "captures editorial work in progress without requiring a dialogue speaker" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Draft line without a speaker", "responses" => []}
        })

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)

      flow_snapshot =
        project_json["flows"]
        |> Enum.find(&(&1["id"] == flow.id))
        |> Map.fetch!("snapshot")

      captured_dialogue = Enum.find(flow_snapshot["nodes"], &(&1["original_id"] == dialogue.id))
      assert captured_dialogue["data"] == dialogue.data
    end

    test "preserves malformed asset relationships in the captured project object" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "relationship bytes #{Ecto.UUID.generate()}")

      raw_relationships = %{
        "original_asset_id" => 999_999_999,
        "web_asset_id" => [asset.id],
        "custom_id" => "content-id",
        "custom_url" => "https://content.invalid/asset",
        "deep_content" => %{
          "one" => %{
            "two" => %{"three" => %{"four" => %{"five" => %{"six" => %{"seven" => %{"eight" => %{"nine" => "exact"}}}}}}}
          }
        },
        "variant_asset_ids" => %{
          "valid-profile" => 888_888_888,
          "INVALID PROFILE" => asset.id
        }
      }

      Repo.update_all(
        from(current in Asset, where: current.id == ^asset.id),
        set: [filename: "../unsafe.png", metadata: raw_relationships]
      )

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)
      manifest = Jason.decode!(capture.manifest_json)
      captured_metadata = project_json["asset_metadata"][to_string(asset.id)]

      assert project_json["asset_restore_contract_version"] ==
               Storyarn.Versioning.Builders.AssetHashResolver.exact_restore_contract_version()

      assert Map.take(captured_metadata, ~w(original_asset_id web_asset_id variant_asset_ids)) ==
               Map.take(raw_relationships, ~w(original_asset_id web_asset_id variant_asset_ids))

      assert captured_metadata["persisted_metadata"] == raw_relationships
      assert captured_metadata["filename"] == "../unsafe.png"

      assert [%{"filename" => manifest_filename, "metadata" => %{}, "relationships" => relationships}] =
               manifest["assets"]

      refute manifest_filename == captured_metadata["filename"]
      assert String.ends_with?(manifest_filename, ".png")
      assert relationships == %{"original" => nil, "web" => nil, "variants" => %{}}
      assert Repo.get!(Asset, asset.id).metadata == raw_relationships
      assert Repo.get!(Asset, asset.id).filename == "../unsafe.png"
    end

    test "preserves nullable asset metadata while keeping the archive manifest valid" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "nullable metadata bytes #{Ecto.UUID.generate()}")

      Repo.update_all(from(current in Asset, where: current.id == ^asset.id), set: [metadata: nil])

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)
      manifest = Jason.decode!(capture.manifest_json)
      captured_metadata = project_json["asset_metadata"][to_string(asset.id)]

      assert Map.has_key?(captured_metadata, "persisted_metadata")
      assert captured_metadata["persisted_metadata"] == nil

      assert [%{"metadata" => %{}, "relationships" => relationships}] = manifest["assets"]
      assert relationships == %{"original" => nil, "web" => nil, "variants" => %{}}
      assert Repo.get!(Asset, asset.id).metadata == nil
    end

    test "captures a verified canonical blob when the persisted asset key is legacy", %{} do
      user = user_fixture()
      project = project_fixture(user)
      contents = "verified bytes with a legacy persisted key"
      asset = upload_asset!(project, user, contents)
      legacy_key = "projects/#{project.id}/legacy-assets/#{asset.id}.png"

      assert {1, nil} =
               Repo.update_all(
                 from(current in Asset, where: current.id == ^asset.id),
                 set: [key: legacy_key]
               )

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)
      manifest = Jason.decode!(capture.manifest_json)
      captured_metadata = project_json["asset_metadata"][to_string(asset.id)]

      assert project_json["asset_blob_hashes"][to_string(asset.id)] == asset.blob_hash
      assert captured_metadata["content_type"] == asset.content_type
      assert captured_metadata["size"] == asset.size
      refute Map.has_key?(captured_metadata, "key")

      assert [%{"sha256" => hash, "size_bytes" => size, "content_type" => "image/png"}] =
               manifest["assets"]

      assert hash == asset.blob_hash
      assert size == byte_size(contents)
      assert capture.source_keys == %{asset.blob_hash => protected_blob_key(project.id, asset)}

      assert Repo.get!(Asset, asset.id).key == legacy_key
    end

    test "captures an exact canonical when the active source is missing" do
      user = user_fixture()
      project = project_fixture(user)
      contents = "exact canonical survives its missing active source"
      asset = upload_asset!(project, user, contents)
      canonical_key = protected_blob_key(project.id, asset)

      assert :ok = Local.delete(asset.key)
      assert {:ok, ^contents} = Local.download(canonical_key)

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      manifest = Jason.decode!(capture.manifest_json)

      assert [%{"sha256" => hash, "size_bytes" => size, "content_type" => "image/png"}] =
               manifest["assets"]

      assert hash == asset.blob_hash
      assert size == asset.size
      assert capture.source_keys == %{asset.blob_hash => canonical_key}

      persisted = Repo.get!(Asset, asset.id)
      assert persisted.blob_hash == asset.blob_hash
      assert persisted.key == asset.key
    end

    test "prefers active project bytes when the persisted hash points at another valid canonical blob" do
      user = user_fixture()
      project = project_fixture(user)
      active_contents = String.duplicate("A", 32)
      stale_contents = String.duplicate("B", 32)
      active_asset = upload_asset!(project, user, active_contents)
      stale_asset = upload_asset!(project, user, stale_contents)
      active_hash = active_asset.blob_hash
      stale_hash = stale_asset.blob_hash

      assert byte_size(active_contents) == byte_size(stale_contents)
      refute active_hash == stale_hash
      assert {:ok, ^stale_contents} = Storage.download(protected_blob_key(project.id, stale_asset))

      assert {1, nil} =
               Repo.update_all(
                 from(current in Asset, where: current.id == ^active_asset.id),
                 set: [blob_hash: stale_hash]
               )

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)
      manifest = Jason.decode!(capture.manifest_json)
      logical_id = project_json["asset_catalog_refs"][to_string(active_asset.id)]
      captured_active_asset = Enum.find(manifest["assets"], &(&1["logical_id"] == logical_id))

      assert project_json["asset_blob_hashes"][to_string(active_asset.id)] == stale_hash
      assert captured_active_asset["sha256"] == active_hash
      assert captured_active_asset["size_bytes"] == byte_size(active_contents)
      assert capture.source_keys[active_hash] == protected_blob_key(project.id, active_asset)
      assert {:ok, ^active_contents} = Storage.download(capture.source_keys[active_hash])

      persisted = Repo.get!(Asset, active_asset.id)
      assert persisted.blob_hash == stale_hash
      assert persisted.key == active_asset.key
    end

    test "captures active bytes from a project blob locator whose embedded hash is stale" do
      user = user_fixture()
      project = project_fixture(user)
      contents = "active bytes outlive their stale blob locator"
      asset = upload_asset!(project, user, contents)
      actual_hash = asset.blob_hash
      stale_hash = BlobStore.compute_hash("different bytes named by the active locator")
      stale_key = BlobStore.blob_key(project.id, stale_hash, "png")
      actual_key = protected_blob_key(project.id, asset)

      refute actual_hash == stale_hash
      assert :ok = Local.delete(asset.key)
      assert :ok = Local.delete(actual_key)
      assert {:ok, _url} = Local.upload(stale_key, contents, "image/png")

      assert {1, nil} =
               Repo.update_all(
                 from(current in Asset, where: current.id == ^asset.id),
                 set: [key: stale_key]
               )

      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)

      assert {:ok, ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      assert {:ok, inspected} = SnapshotArchiveStorage.inspect_ready_archive(ready)
      assert [%{"sha256" => ^actual_hash, "blob_path" => blob_path}] = inspected.manifest["assets"]
      assert {:ok, archive} = Storage.download(ready.archive_storage_key)
      assert {:ok, entries} = :zip.extract(archive, [:memory])
      extracted = Map.new(entries, fn {path, bytes} -> {List.to_string(path), bytes} end)
      project_json = extracted |> Map.fetch!("project.json") |> Jason.decode!()

      assert extracted[blob_path] == contents
      assert project_json["asset_blob_hashes"][to_string(asset.id)] == actual_hash
      assert {:ok, ^contents} = Local.download(actual_key)

      persisted = Repo.get!(Asset, asset.id)
      assert persisted.blob_hash == actual_hash
      assert persisted.key == stale_key
    end

    test "derives a verified manifest identity from a project-owned source when technical fields drift" do
      user = user_fixture()
      project = project_fixture(user)
      contents = "bytes remain authoritative despite nullable legacy identity"
      asset = upload_asset!(project, user, contents)
      expected_hash = BlobStore.compute_hash(contents)
      canonical_key = protected_blob_key(project.id, asset)

      assert :ok = Local.delete(canonical_key)

      assert {1, nil} =
               Repo.update_all(
                 from(current in Asset, where: current.id == ^asset.id),
                 set: [blob_hash: nil, size: -7, content_type: "legacy/unknown"]
               )

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      project_json = Jason.decode!(capture.project_json)
      manifest = Jason.decode!(capture.manifest_json)
      captured_metadata = project_json["asset_metadata"][to_string(asset.id)]

      assert project_json["asset_blob_hashes"][to_string(asset.id)] == nil
      assert captured_metadata["content_type"] == "legacy/unknown"
      assert captured_metadata["size"] == -7

      assert [%{"sha256" => ^expected_hash, "size_bytes" => size, "content_type" => "image/png"}] =
               manifest["assets"]

      assert size == byte_size(contents)
      assert capture.source_keys == %{expected_hash => canonical_key}
      assert {:ok, ^contents} = Storage.download(canonical_key)

      persisted = Repo.get!(Asset, asset.id)
      assert persisted.blob_hash == nil
      assert persisted.size == -7
      assert persisted.content_type == "legacy/unknown"
    end

    test "normalizes one manifest MIME for active assets that share the same verified bytes" do
      user = user_fixture()
      project = project_fixture(user)
      contents = "same bytes with conflicting persisted MIME semantics"

      assert {:ok, png_asset} =
               Assets.upload_binary_and_create_asset(
                 contents,
                 %{filename: "shared.png", content_type: "image/png"},
                 project,
                 user
               )

      assert {:ok, pdf_asset} =
               Assets.upload_binary_and_create_asset(
                 contents,
                 %{filename: "shared.pdf", content_type: "application/pdf"},
                 project,
                 user
               )

      assert png_asset.blob_hash == pdf_asset.blob_hash
      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      manifest = Jason.decode!(capture.manifest_json)

      assert captured.blob_count == 1
      assert Enum.map(manifest["assets"], & &1["content_type"]) == ["application/pdf", "application/pdf"]
      assert Enum.map(manifest["assets"], & &1["sha256"]) == [png_asset.blob_hash, png_asset.blob_hash]

      assert Repo.get!(Asset, png_asset.id).content_type == "image/png"
      assert Repo.get!(Asset, pdf_asset.id).content_type == "application/pdf"
    end

    test "repairs a missing normalized canonical blob from a verified raw-MIME canonical" do
      user = user_fixture()
      project = project_fixture(user)
      contents = "same bytes survive normalized canonical loss"

      assert {:ok, png_asset} =
               Assets.upload_binary_and_create_asset(
                 contents,
                 %{filename: "shared.png", content_type: "image/png"},
                 project,
                 user
               )

      assert {:ok, pdf_asset} =
               Assets.upload_binary_and_create_asset(
                 contents,
                 %{filename: "shared.pdf", content_type: "application/pdf"},
                 project,
                 user
               )

      png_blob_key = protected_blob_key(project.id, png_asset)
      pdf_blob_key = protected_blob_key(project.id, pdf_asset)
      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :capture_inventory_observed_fun, fn
          :captured, _assets ->
            assert :ok = Local.delete(pdf_blob_key)
            assert :ok = Local.delete(png_asset.key)
            assert :ok = Local.delete(pdf_asset.key)
            assert {:ok, ^contents} = Local.download(png_blob_key)
            :ok

          _stage, _assets ->
            :ok
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      manifest = Jason.decode!(capture.manifest_json)

      assert Enum.map(manifest["assets"], & &1["content_type"]) == ["application/pdf", "application/pdf"]
      assert capture.source_keys == %{png_asset.blob_hash => pdf_blob_key}
      assert {:ok, ^contents} = Local.download(pdf_blob_key)
    end

    test "finds a verified canonical blob stored under a legacy MIME extension" do
      user = user_fixture()
      project = project_fixture(user)
      contents = "canonical bytes beneath a legacy extension"
      asset = upload_asset!(project, user, contents)
      hash = asset.blob_hash
      legacy_content_type = "application/x-storyarn-legacy"
      legacy_extension = BlobStore.ext_from_content_type(legacy_content_type)
      legacy_blob_key = BlobStore.blob_key(project.id, hash, legacy_extension)

      assert {:ok, _url} = Storage.upload(legacy_blob_key, contents, legacy_content_type)
      assert :ok = Local.delete(protected_blob_key(project.id, asset))
      assert :ok = Local.delete(asset.key)

      assert {1, nil} =
               Repo.update_all(
                 from(current in Asset, where: current.id == ^asset.id),
                 set: [content_type: legacy_content_type, key: "projects/#{project.id}/legacy-assets/missing.bin"]
               )

      assert {:ok, requested} = request_snapshot(user, project)
      captured = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, captured.id)
      manifest = Jason.decode!(capture.manifest_json)
      generic_key = BlobStore.blob_key(project.id, hash, "bin")

      assert [%{"sha256" => ^hash, "content_type" => "application/octet-stream"}] = manifest["assets"]
      assert capture.source_keys == %{hash => generic_key}
      assert {:ok, ^contents} = Storage.download(generic_key)
      assert Repo.get!(Asset, asset.id).content_type == legacy_content_type
    end

    test "captures an empty but readable legacy source as a zero-byte blob" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "original non-empty bytes")
      old_canonical_key = protected_blob_key(project.id, asset)
      empty_hash = BlobStore.compute_hash("")

      assert :ok = Local.delete(old_canonical_key)
      assert {:ok, _url} = Storage.upload(asset.key, "", "image/png")

      assert {1, nil} =
               Repo.update_all(
                 from(current in Asset, where: current.id == ^asset.id),
                 set: [blob_hash: nil, size: -1, content_type: "legacy/unknown"]
               )

      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)

      assert {:ok, ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      assert ready.lifecycle_state == "ready"

      assert {:ok, inspected} = SnapshotArchiveStorage.inspect_ready_archive(ready)
      manifest = inspected.manifest
      empty_blob_key = BlobStore.blob_key(project.id, empty_hash, "png")

      assert [
               %{
                 "sha256" => ^empty_hash,
                 "size_bytes" => 0,
                 "content_type" => "image/png",
                 "blob_path" => blob_path
               }
             ] = manifest["assets"]

      assert {:ok, ""} = Storage.download(empty_blob_key)

      assert {:ok, archive} = Storage.download(ready.archive_storage_key)
      assert {:ok, entries} = :zip.extract(archive, [:memory])
      extracted = Map.new(entries, fn {path, bytes} -> {List.to_string(path), bytes} end)
      assert extracted[blob_path] == ""
      assert Repo.get!(Asset, asset.id).size == -1
    end

    test "heartbeat rejects a build job outside the canonical archive queue" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      now = TimeHelpers.now()

      job =
        snapshot
        |> requested_job()
        |> Ecto.Changeset.change(
          state: "executing",
          attempted_at: %{now | microsecond: {0, 6}}
        )
        |> Repo.update!()

      assert job.queue == "snapshot_archives"

      misrouted_job =
        job
        |> Ecto.Changeset.change(queue: "default")
        |> Repo.update!()

      assert misrouted_job.queue == "default"

      handler_id = "snapshot-build-misrouting-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :build, :heartbeat],
          fn _event, measurements, metadata, pid ->
            send(pid, {:snapshot_build_heartbeat, measurements, metadata})
          end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:error, :snapshot_build_not_active} =
               Versioning.heartbeat_project_snapshot_build(snapshot.id, job.id)

      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :rejected, snapshot_id: snapshot_id}}
      assert snapshot_id == snapshot.id
    end

    test "heartbeat is fenced and lifecycle time stays monotonic under clock skew" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      now = TimeHelpers.now()

      building =
        requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      job =
        building.build_job_id
        |> then(&Repo.get!(Oban.Job, &1))
        |> Ecto.Changeset.change(
          state: "executing",
          attempted_at: %{now | microsecond: {0, 6}}
        )
        |> Repo.update!()

      reservation = Repo.get!(StorageReservation, building.storage_reservation_id)

      reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: now,
        expires_at: DateTime.add(now, 24 * 60 * 60, :second)
      )
      |> Repo.update!()

      claim =
        building.object_prefix
        |> SnapshotObjectPublicationClaim.create_changeset(
          String.duplicate("a", 64),
          Ecto.UUID.generate(),
          DateTime.add(now, 1, :second),
          reservation.id,
          reservation.lease_token
        )
        |> Repo.insert!()

      building
      |> ProjectSnapshot.build_state_changeset(%{
        publication_claim_token: claim.claim_token,
        state_updated_at: now
      })
      |> Repo.update!()

      handler_id = "snapshot-build-heartbeat-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :build, :heartbeat],
          fn _event, measurements, metadata, pid ->
            send(pid, {:snapshot_build_heartbeat, measurements, metadata})
          end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      database_before = database_clock_now()
      assert :ok = Versioning.heartbeat_project_snapshot_build(building.id, job.id)
      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :renewed, snapshot_id: snapshot_id}}
      assert snapshot_id == building.id
      database_after = database_clock_now()
      heartbeat_at = Repo.get!(ProjectSnapshot, building.id).state_updated_at
      renewed_reservation = Repo.get!(StorageReservation, reservation.id)
      renewed_claim = Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix)
      assert DateTime.compare(heartbeat_at, building.state_updated_at) in [:eq, :gt]
      assert DateTime.compare(heartbeat_at, database_before) in [:eq, :gt]
      assert DateTime.compare(heartbeat_at, database_after) in [:eq, :lt]
      assert renewed_reservation.generation == reservation.generation + 1
      assert DateTime.after?(renewed_reservation.expires_at, database_after)
      assert DateTime.after?(renewed_claim.lease_expires_at, database_after)

      claim_lease_ttl = Versioning.project_snapshot_build_lease_ttl_seconds()

      assert DateTime.diff(renewed_claim.lease_expires_at, database_before, :second) in (claim_lease_ttl - 1)..(claim_lease_ttl +
                                                                                                                  1)

      assert DateTime.diff(
               renewed_reservation.expires_at,
               renewed_reservation.accounting_measured_at,
               :second
             ) == Versioning.project_snapshot_build_lease_ttl_seconds()

      renewed_reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(database_after, -120, :second),
        expires_at: DateTime.add(database_after, -60, :second)
      )
      |> Repo.update!()

      expired_claim_lease = DateTime.add(database_after, -60, :second)

      renewed_claim
      |> Ecto.Changeset.change(lease_expires_at: expired_claim_lease)
      |> Repo.update!()

      assert Repo.get!(Oban.Job, job.id).queue == "snapshot_archives"

      assert {:error, :snapshot_build_not_active} =
               Versioning.heartbeat_project_snapshot_build(building.id, job.id)

      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :rejected, snapshot_id: snapshot_id}}
      assert snapshot_id == building.id
      unchanged_reservation = Repo.get!(StorageReservation, reservation.id)
      expired_claim = Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix)
      assert unchanged_reservation.generation == renewed_reservation.generation
      assert DateTime.before?(unchanged_reservation.expires_at, database_clock_now())
      assert expired_claim.lease_expires_at == expired_claim_lease
      assert DateTime.before?(expired_claim.lease_expires_at, database_clock_now())

      future = DateTime.add(database_after, 300, :second)
      skew_before = database_clock_now()
      normalized = building |> ProjectSnapshot.build_state_changeset(%{state_updated_at: future}) |> Repo.update!()
      skew_after = database_clock_now()
      assert DateTime.compare(normalized.state_updated_at, skew_before) in [:eq, :gt]
      assert DateTime.compare(normalized.state_updated_at, skew_after) in [:eq, :lt]
      assert DateTime.before?(normalized.state_updated_at, future)

      assert {:ok, caught_up} =
               normalized
               |> ProjectSnapshot.build_state_changeset(%{progress_bytes: 1, state_updated_at: database_after})
               |> Repo.update()

      assert DateTime.compare(caught_up.state_updated_at, normalized.state_updated_at) in [:eq, :gt]
      assert caught_up.progress_bytes == 1

      caught_up |> ProjectSnapshot.cancel_request_changeset(TimeHelpers.now()) |> Repo.update!()

      assert {:error, :snapshot_build_not_active} =
               Versioning.heartbeat_project_snapshot_build(building.id, job.id)

      assert_receive {:snapshot_build_heartbeat, %{count: 1}, %{outcome: :rejected, snapshot_id: snapshot_id}}
      assert snapshot_id == building.id
    end
  end

  describe "perform_project_snapshot_build/2" do
    test "logs a safe structured capture reason without leaking exception details" do
      user = user_fixture()
      project = project_fixture(user)
      secret_detail = "{:invalid_avatar_reference, 918273}"
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :capture_inventory_observed_fun, fn
          :repaired, _assets ->
            raise ArgumentError,
                  "cannot build a flow snapshot with invalid external references: #{secret_detail}"

          _stage, _assets ->
            :ok
        end)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)
      end)

      log =
        capture_log(fn ->
          assert {:error, :snapshot_capture_failed} =
                   ProjectSnapshotBuild.materialize_capture(requested.id, job.id)
        end)

      assert log =~ "Project snapshot capture failed safely"
      assert log =~ "event=project_snapshot_capture_failed"
      assert log =~ "snapshot_id=#{requested.id}"
      assert log =~ "job_id=#{job.id}"
      assert log =~ "reason_code=invalid_flow_external_reference"
      assert log =~ "failure_origin=flow_builder"
      assert log =~ "exception_module=ArgumentError"
      refute log =~ secret_detail
      refute log =~ "918273"
      refute log =~ "invalid_avatar_reference"
    end

    test "publishes only the immutable capture after current asset deletion" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      asset = upload_asset!(project, user, "durable snapshot bytes")

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project, %{title: "Milestone"})
      assert Notifications.list_notifications(scope) == []
      refute_receive :notifications_changed

      requested = materialize_snapshot_capture!(requested)
      assert {:ok, _deleted} = Assets.delete_asset(asset)
      assert :ok = Storage.delete(asset.key)

      assert :ok = perform_requested_job(requested)
      assert_receive :notifications_changed

      ready = Repo.get!(ProjectSnapshot, requested.id)
      assert ready.lifecycle_state == "ready"
      assert ready.integrity_state == "verified"
      assert ready.format_version == 2
      assert ready.object_count == 2
      assert ready.progress_phase == "complete"
      assert ready.progress_bytes == ready.total_size_bytes
      assert ready.ready_at

      assert %StorageReservation{status: "committed", actual_bytes: actual_bytes} =
               Repo.get!(StorageReservation, ready.storage_reservation_id)

      assert actual_bytes == ready.total_size_bytes

      assert {:ok, inspected} = SnapshotArchiveStorage.inspect_ready_archive(ready)
      assert inspected.verified_objects == 2
      assert inspected.verified_bytes == ready.total_size_bytes

      assert [%{"filename" => filename, "blob_path" => blob_path}] =
               inspected.manifest["assets"]

      assert filename == asset.filename
      assert {:ok, archive} = Storage.download(ready.archive_storage_key)
      assert {:ok, sidecar} = Storage.download(ready.manifest_storage_key)
      assert {:ok, entries} = :zip.extract(archive, [:memory])
      extracted = Map.new(entries, fn {path, bytes} -> {List.to_string(path), bytes} end)
      assert extracted[blob_path] == "durable snapshot bytes"
      assert extracted["manifest.json"] == sidecar
      refute Repo.get(ProjectSnapshotCapture, ready.id)

      assert {:ok, %{objects: ready_objects, cursor: nil}} =
               Storage.list_prefix(ready.object_prefix <> "/", limit: 10)

      assert Enum.map(ready_objects, & &1.key) ==
               Enum.sort([ready.archive_storage_key, ready.manifest_storage_key])

      assert_snapshot_notification(scope, ready, "success", "Milestone")

      assert :ok = perform_requested_job(ready)
      refute_receive :notifications_changed
      assert_snapshot_notification(scope, ready, "success", "Milestone")
      assert Repo.get!(ProjectSnapshot, ready.id).accounting_generation == 1
    end

    test "finalizes ready when the requester is nilified after advisory identity and suppresses notification" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      _asset = upload_asset!(project, user, "requester race")

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project, %{title: "Requester race"})
      requested = materialize_snapshot_capture!(requested)

      original_config = Application.get_env(:storyarn, StorageAccounting, [])
      parent = self()

      Application.put_env(
        :storyarn,
        StorageAccounting,
        Keyword.put(original_config, :snapshot_target_identity_observed_fun, fn identity ->
          if identity.snapshot_id == requested.id and is_integer(identity.created_by_id) do
            assert {1, nil} =
                     Repo.update_all(
                       from(snapshot in ProjectSnapshot,
                         where:
                           snapshot.id == ^identity.snapshot_id and
                             snapshot.created_by_id == ^identity.created_by_id
                       ),
                       set: [created_by_id: nil]
                     )

            send(parent, :snapshot_ready_requester_nilified)
          end

          :ok
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, StorageAccounting, original_config) end)

      assert :ok = perform_requested_job(requested)
      assert_receive :snapshot_ready_requester_nilified
      refute_receive :notifications_changed

      assert %ProjectSnapshot{lifecycle_state: "ready", created_by_id: nil} =
               Repo.get!(ProjectSnapshot, requested.id)

      assert Notifications.list_notifications(scope) == []
    end

    test "retries the published namespace when staging cleanup has no durable owner" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      original_config = Application.get_env(:storyarn, SnapshotArchiveStorage, [])

      Application.put_env(
        :storyarn,
        SnapshotArchiveStorage,
        original_config
        |> Keyword.put(:cleanup_delete_fun, fn keys -> {:error, keys} end)
        |> Keyword.put(:cleanup_persist_fun, fn _keys -> {:error, :database_unavailable} end)
      )

      on_exit(fn -> Application.put_env(:storyarn, SnapshotArchiveStorage, original_config) end)

      assert {:snooze, 30} = perform_requested_job(requested)

      recovering = Repo.get!(ProjectSnapshot, requested.id)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)

      assert recovering.lifecycle_state == "verifying"
      assert recovering.object_prefix == requested.object_prefix
      assert reservation.status == "active"
      assert claim.status == "published"
      assert Repo.get!(ProjectSnapshotCapture, requested.id)
      assert {:ok, _stat} = Storage.stat(requested.archive_storage_key)
      assert {:ok, _stat} = Storage.stat(requested.manifest_storage_key)

      Application.put_env(:storyarn, SnapshotArchiveStorage, original_config)

      assert :ok = perform_requested_job(recovering)
      assert Repo.get!(ProjectSnapshot, requested.id).lifecycle_state == "ready"
      refute Repo.get(ProjectSnapshotCapture, requested.id)
    end

    test "a discarded old writer cannot resume past its current object or publish a ready snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      parent = self()
      release_ref = make_ref()
      original_storage_config = Application.get_env(:storyarn, :storage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn path, data ->
          send(parent, {:snapshot_stage_write_paused, self(), path})

          receive do
            {:resume_snapshot_stage_write, ^release_ref} -> File.write(path, data, [:binary, :exclusive])
          after
            5_000 -> {:error, :paused_snapshot_stage_write_timeout}
          end
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage_config) end)

      build_task = Task.async(fn -> BuildProjectSnapshotWorker.perform(job) end)
      assert_receive {:snapshot_stage_write_paused, writer, _path}, 2_000

      active_reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      active_claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)
      expired_at = DateTime.add(database_clock_now(), -1, :second)

      active_reservation
      |> Ecto.Changeset.change(
        expires_at: expired_at,
        accounting_measured_at: DateTime.add(expired_at, -1, :second)
      )
      |> Repo.update!()

      active_claim
      |> SnapshotObjectPublicationClaim.status_changeset("staging", expired_at)
      |> Repo.update!()

      set_stale_build_heartbeat_seconds(0)

      assert %{failure_count: 0, orphaned_count: 1, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert {:error, :snapshot_build_job_not_executing} =
               Versioning.validate_project_snapshot_build_fence(
                 requested.id,
                 requested.lifecycle_generation
               )

      send(writer, {:resume_snapshot_stage_write, release_ref})
      assert {:discard, :snapshot_build_job_not_executing} = Task.await(build_task, 5_000)

      refute Repo.get!(ProjectSnapshot, requested.id).lifecycle_state == "ready"
      assert Repo.get!(Oban.Job, job.id).state == "discarded"
      assert {:error, _reason} = Storage.stat(requested.manifest_storage_key)

      staging_archive_key =
        String.replace(requested.archive_storage_key, "/ready/", "/staging/", global: false)

      assert {:ok, _stat} = Storage.stat(staging_archive_key)

      released = Repo.get!(StorageReservation, requested.storage_reservation_id)
      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert "storage_cleanup_request:" <> cleanup_request_id = released.cleanup_reference

      cleanup_request = Repo.get!(StorageCleanupRequest, String.to_integer(cleanup_request_id))
      assert staging_archive_key in cleanup_request.storage_keys
      assert requested.manifest_storage_key in cleanup_request.storage_keys
    end

    test "repairs a missing protected source from the verified active asset before capture" do
      user = user_fixture()
      project = project_fixture(user)
      content = "repairable legacy source"
      asset = upload_asset!(project, user, content)

      _sheet =
        Storyarn.SheetsFixtures.sheet_fixture(project, %{
          name: "Legacy asset reference",
          banner_asset_id: asset.id
        })

      assert {:ok, requested} = request_snapshot(user, project)
      blob_key = protected_blob_key(project.id, asset)
      assert :ok = Local.delete(blob_key)

      job = requested_job(requested)

      assert {:ok, :captured} =
               ProjectSnapshotBuild.materialize_capture(requested.id, job.id)

      assert {:ok, ^content} = Storage.download(blob_key)

      assert %ProjectSnapshotCapture{source_keys: source_keys} =
               Repo.get!(ProjectSnapshotCapture, requested.id)

      assert Map.values(source_keys) == [blob_key]
    end

    test "repairs exactly the captured inventory when a trashed asset is restored after capture" do
      user = user_fixture()
      project = project_fixture(user)
      captured_asset = upload_asset!(project, user, "captured inventory bytes")
      restored_later = upload_asset!(project, user, "restored after inventory capture")

      assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, restored_later.id, user.id)
      restored_blob_key = protected_blob_key(project.id, restored_later)
      assert :ok = Local.delete(restored_blob_key)

      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      captured_blob_key = protected_blob_key(project.id, captured_asset)
      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      parent = self()
      observed_ref = make_ref()

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :capture_inventory_observed_fun, fn
          :captured, assets ->
            if !Process.get(observed_ref) do
              Process.put(observed_ref, true)
              assert Enum.map(assets, & &1.id) == [captured_asset.id]
              refute Repo.in_transaction?()

              assert {:ok, _trashed_captured} =
                       Assets.move_asset_to_trash(project.id, captured_asset.id, user.id)

              assert {:ok, restored} =
                       Assets.restore_trashed_asset(
                         project.id,
                         trashed.id,
                         trashed.deletion_generation,
                         user.id
                       )

              assert is_nil(restored.deleted_at)
              assert :ok = Local.delete(captured_blob_key)
              send(parent, {:snapshot_exact_inventory_observed, Repo.in_transaction?()})
            end

            :ok

          _stage, _assets ->
            :ok
        end)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)
      end)

      assert {:ok, :captured} = ProjectSnapshotBuild.materialize_capture(requested.id, job.id)
      assert_receive {:snapshot_exact_inventory_observed, false}

      capture = Repo.get!(ProjectSnapshotCapture, requested.id)
      assert capture.asset_count == 1
      assert capture.source_keys == %{captured_asset.blob_hash => captured_blob_key}
      refute Map.has_key?(capture.source_keys, restored_later.blob_hash)
      assert {:ok, "captured inventory bytes"} = Local.download(captured_blob_key)
      assert {:error, :enoent} = Local.download(restored_blob_key)
    end

    test "rechecks and repairs active inventory changes before snapshot builders run" do
      user = user_fixture()
      project = project_fixture(user)
      stable_asset = upload_asset!(project, user, "stable inventory bytes")
      restored_later = upload_asset!(project, user, "restored referenced banner")

      assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, restored_later.id, user.id)

      sheet = Storyarn.SheetsFixtures.sheet_fixture(project, %{name: "Restored banner"})

      assert {1, nil} =
               Repo.update_all(
                 from(candidate in Sheet, where: candidate.id == ^sheet.id),
                 set: [banner_asset_id: restored_later.id]
               )

      restored_blob_key = protected_blob_key(project.id, restored_later)
      assert :ok = Local.delete(restored_blob_key)

      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      parent = self()
      observed_ref = make_ref()

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :capture_inventory_observed_fun, fn
          :repaired, assets ->
            if !Process.get(observed_ref) do
              Process.put(observed_ref, true)
              assert Enum.map(assets, & &1.id) == [stable_asset.id]
              refute Repo.in_transaction?()

              assert {:ok, restored} =
                       Assets.restore_trashed_asset(
                         project.id,
                         trashed.id,
                         trashed.deletion_generation,
                         user.id
                       )

              send(parent, {:snapshot_inventory_changed_after_repair, restored.id, Repo.in_transaction?()})
            end

            :ok

          _stage, _assets ->
            :ok
        end)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)
      end)

      assert {:ok, :captured} = ProjectSnapshotBuild.materialize_capture(requested.id, job.id)
      assert_receive {:snapshot_inventory_changed_after_repair, restored_id, false}
      assert restored_id == restored_later.id

      capture = Repo.get!(ProjectSnapshotCapture, requested.id)
      assert capture.asset_count == 2

      assert capture.source_keys == %{
               stable_asset.blob_hash => protected_blob_key(project.id, stable_asset),
               restored_later.blob_hash => restored_blob_key
             }

      assert {:ok, "restored referenced banner"} = Local.download(restored_blob_key)
    end

    test "a legacy five-attempt job repairs its immutable captured asset provenance" do
      user = user_fixture()
      project = project_fixture(user)
      captured_asset = upload_asset!(project, user, "legacy captured source")

      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      assert {:ok, :captured} = ProjectSnapshotBuild.materialize_capture(requested.id, job.id)

      capture_before = Repo.get!(ProjectSnapshotCapture, requested.id)
      captured_blob_key = protected_blob_key(project.id, captured_asset)
      assert capture_before.source_keys == %{captured_asset.blob_hash => captured_blob_key}

      assert {:ok, _trashed} = Assets.move_asset_to_trash(project.id, captured_asset.id, user.id)
      current_asset = upload_asset!(project, user, "current asset outside legacy capture")
      refute current_asset.blob_hash == captured_asset.blob_hash
      assert :ok = Local.delete(protected_blob_key(project.id, current_asset))
      assert :ok = Local.delete(current_asset.key)
      assert :ok = Local.delete(captured_blob_key)

      legacy_job =
        job
        |> Ecto.Changeset.change(
          attempt: 4,
          max_attempts: 5,
          errors: [%{"attempt" => 1}, %{"attempt" => 2}, %{"attempt" => 3}]
        )
        |> Repo.update!()

      assert {:ok, :already_captured} =
               ProjectSnapshotBuild.materialize_capture(requested.id, legacy_job.id)

      capture_after = Repo.get!(ProjectSnapshotCapture, requested.id)
      assert capture_after.capture_digest == capture_before.capture_digest
      assert capture_after.project_json == capture_before.project_json
      assert capture_after.manifest_json == capture_before.manifest_json
      assert capture_after.source_keys == capture_before.source_keys
      assert {:ok, "legacy captured source"} = Local.download(captured_blob_key)

      assert :ok = Local.delete(captured_blob_key)
      assert :ok = BuildProjectSnapshotWorker.perform(legacy_job)

      ready = Repo.get!(ProjectSnapshot, requested.id)
      assert ready.lifecycle_state == "ready"
      refute Repo.get(ProjectSnapshotCapture, requested.id)

      assert {:ok, manifest_json} = Storage.download(ready.manifest_storage_key)
      manifest = Jason.decode!(manifest_json)
      assert Enum.map(manifest["assets"], & &1["sha256"]) == [captured_asset.blob_hash]
      refute Enum.any?(manifest["assets"], &(&1["sha256"] == current_asset.blob_hash))
    end

    test "repairs a sanitized SVG from immutable legacy capture provenance" do
      user = user_fixture()
      project = project_fixture(user)
      svg = ~S(<svg xmlns="http://www.w3.org/2000/svg"><circle cx="4" cy="4" r="3"/></svg>)

      assert {:ok, asset} =
               Assets.upload_sanitized_svg_and_create_asset(
                 svg,
                 %{filename: "snapshot.svg", content_type: "image/svg+xml"},
                 project,
                 user
               )

      assert asset.metadata["sanitized_svg"] == true
      assert {:ok, source_bytes} = Local.download(asset.key)
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      assert {:ok, :captured} = ProjectSnapshotBuild.materialize_capture(requested.id, job.id)

      capture_before = Repo.get!(ProjectSnapshotCapture, requested.id)
      blob_key = protected_blob_key(project.id, asset)
      assert capture_before.source_keys == %{asset.blob_hash => blob_key}

      assert {:ok, _trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)
      assert :ok = Local.delete(blob_key)

      assert {:ok, :already_captured} =
               ProjectSnapshotBuild.materialize_capture(requested.id, job.id)

      capture_after = Repo.get!(ProjectSnapshotCapture, requested.id)
      assert capture_after.capture_digest == capture_before.capture_digest
      assert capture_after.source_keys == capture_before.source_keys
      assert {:ok, ^source_bytes} = Local.download(blob_key)
    end

    test "legacy repair never substitutes an equivalent asset outside captured provenance" do
      user = user_fixture()
      project = project_fixture(user)
      content = "captured provenance only"
      captured_asset = upload_asset!(project, user, content)

      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)
      assert {:ok, :captured} = ProjectSnapshotBuild.materialize_capture(requested.id, job.id)

      assert {:ok, _trashed} = Assets.move_asset_to_trash(project.id, captured_asset.id, user.id)
      Repo.delete!(Repo.get!(Asset, captured_asset.id))

      equivalent_current = upload_asset!(project, user, content)
      assert equivalent_current.blob_hash == captured_asset.blob_hash

      blob_key = protected_blob_key(project.id, captured_asset)
      assert :ok = Local.delete(blob_key)

      assert {:error, {:missing_snapshot_blob_source, blob_hash}} =
               ProjectSnapshotBuild.materialize_capture(requested.id, job.id)

      assert blob_hash == captured_asset.blob_hash
      assert {:error, :enoent} = Local.download(blob_key)
      assert Repo.get!(ProjectSnapshotCapture, requested.id).source_keys == %{captured_asset.blob_hash => blob_key}
    end

    test "fails closed when the protected blob and original asset are missing" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      asset = upload_asset!(project, user, "missing source")

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project, %{title: "Broken milestone"})
      refute_receive :notifications_changed

      assert :ok = Local.delete(protected_blob_key(project.id, asset))
      assert :ok = Local.delete(asset.key)

      job = requested_job(requested)

      assert {:discard, :source_missing} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      assert_receive :notifications_changed

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.integrity_state == "missing"
      assert failed.failure_code == "source_missing"
      assert failed.failed_at
      assert {:error, _reason} = Storage.stat(failed.manifest_storage_key)
      assert Repo.get!(StorageReservation, failed.storage_reservation_id).status == "released"
      refute Repo.get(ProjectSnapshotCapture, failed.id)
      assert_snapshot_notification(scope, failed, "failure", "Broken milestone")
    end

    test "terminalizes failure when the requester is nilified after advisory identity and suppresses notification" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      asset = upload_asset!(project, user, "missing requester race")

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project, %{title: "Missing requester"})
      assert :ok = Local.delete(protected_blob_key(project.id, asset))
      assert :ok = Local.delete(asset.key)

      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      parent = self()

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :terminal_identity_observed_fun, fn identity ->
          if identity.snapshot_id == requested.id and is_integer(identity.created_by_id) do
            assert {1, nil} =
                     Repo.update_all(
                       from(snapshot in ProjectSnapshot,
                         where:
                           snapshot.id == ^identity.snapshot_id and
                             snapshot.created_by_id == ^identity.created_by_id
                       ),
                       set: [created_by_id: nil]
                     )

            send(parent, :snapshot_failure_requester_nilified)
          end

          :ok
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      job = requested_job(requested)

      assert {:discard, :source_missing} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      assert_receive :snapshot_failure_requester_nilified
      refute_receive :notifications_changed

      assert %ProjectSnapshot{
               lifecycle_state: "failed",
               integrity_state: "missing",
               created_by_id: nil
             } = Repo.get!(ProjectSnapshot, requested.id)

      assert Notifications.list_notifications(scope) == []
    end

    test "captures current active bytes when the persisted identity is stale" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "trusted source")
      active_contents = "tampered bytes"
      active_hash = BlobStore.compute_hash(active_contents)

      assert {:ok, requested} = request_snapshot(user, project)
      stale_blob_key = protected_blob_key(project.id, asset)
      active_blob_key = BlobStore.blob_key(project.id, active_hash, "png")
      assert {:ok, _url} = Local.upload(stale_blob_key, active_contents, "image/png")
      assert {:ok, _url} = Local.upload(asset.key, active_contents, "image/png")

      job = requested_job(requested)

      assert {:ok, ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      assert {:ok, inspected} = SnapshotArchiveStorage.inspect_ready_archive(ready)
      manifest = inspected.manifest
      assert {:ok, archive} = Storage.download(ready.archive_storage_key)
      assert {:ok, entries} = :zip.extract(archive, [:memory])
      extracted = Map.new(entries, fn {path, bytes} -> {List.to_string(path), bytes} end)
      project_json = extracted |> Map.fetch!("project.json") |> Jason.decode!()

      assert ready.lifecycle_state == "ready"
      assert ready.integrity_state == "verified"
      assert project_json["asset_blob_hashes"][to_string(asset.id)] == asset.blob_hash
      assert [%{"sha256" => ^active_hash, "size_bytes" => 14, "blob_path" => blob_path}] = manifest["assets"]
      assert extracted[blob_path] == active_contents
      assert {:ok, ^active_contents} = Local.download(active_blob_key)

      assert Repo.get!(StorageReservation, ready.storage_reservation_id).status == "committed"
      assert Repo.get!(Asset, asset.id).blob_hash == asset.blob_hash
      assert {:ok, ^active_contents} = Local.download(stale_blob_key)
      refute Repo.get(ProjectSnapshotCapture, ready.id)
    end

    test "publishes divergent active bytes without entering corruption cleanup" do
      user = user_fixture()
      project = project_fixture(user)
      asset = upload_asset!(project, user, "trusted source")
      active_contents = "tampered bytes"

      assert {:ok, requested} = request_snapshot(user, project)
      assert {:ok, _url} = Local.upload(protected_blob_key(project.id, asset), active_contents, "image/png")
      assert {:ok, _url} = Local.upload(asset.key, active_contents, "image/png")

      job = requested_job(requested)
      original_snapshot_config = Application.get_env(:storyarn, SnapshotArchiveStorage, [])
      parent = self()

      Application.put_env(
        :storyarn,
        SnapshotArchiveStorage,
        Keyword.put(original_snapshot_config, :cleanup_persist_fun, fn _keys ->
          send(parent, :snapshot_staging_cleanup_attempted)
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, SnapshotArchiveStorage, original_snapshot_config) end)

      assert {:ok, ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 2
               )

      refute_receive :snapshot_staging_cleanup_attempted
      assert ready.lifecycle_state == "ready"
      assert ready.integrity_state == "verified"
      assert Repo.get!(StorageReservation, requested.storage_reservation_id).status == "committed"
      refute Repo.get(ProjectSnapshotCapture, ready.id)
    end

    test "allocates a fresh owned namespace and reservation before retrying" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      _asset = upload_asset!(project, user, "retryable source")

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      job = requested_job(requested)
      original_storage_config = Application.get_env(:storyarn, :storage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn _path, _data ->
          {:error, :eio}
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage_config) end)

      assert {:retry, :build_failed} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 2
               )

      refute_receive :notifications_changed
      assert Notifications.list_notifications(scope) == []

      retrying = Repo.get!(ProjectSnapshot, requested.id)
      assert retrying.lifecycle_state == "pending"
      assert retrying.progress_phase == "retrying"
      assert retrying.object_prefix != requested.object_prefix
      assert retrying.storage_reservation_id != requested.storage_reservation_id
      assert Repo.get!(StorageReservation, requested.storage_reservation_id).status == "released"
      assert Repo.get!(StorageReservation, retrying.storage_reservation_id).status == "active"

      Application.put_env(:storyarn, :storage, original_storage_config)

      assert {:ok, %ProjectSnapshot{lifecycle_state: "ready"}} =
               Versioning.perform_project_snapshot_build(retrying.id,
                 job_id: job.id,
                 attempt: 2,
                 max_attempts: 2
               )

      assert_receive :notifications_changed

      ready = Repo.get!(ProjectSnapshot, requested.id)
      assert ready.lifecycle_state == "ready"
      assert ready.integrity_state == "verified"
      assert ready.object_prefix == retrying.object_prefix
      assert Repo.get!(StorageReservation, ready.storage_reservation_id).status == "committed"
      assert_snapshot_notification(scope, ready, "success", nil)
    end

    test "cancellation after release fences retry allocation without creating another reservation" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      _asset = upload_asset!(project, user, "cancel retry race source")
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      job = requested_job(requested)
      original_storage_config = Application.get_env(:storyarn, :storage, [])
      handler_id = "snapshot-retry-cancel-race-#{System.unique_integer([:positive])}"
      parent = self()

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn _path, _data ->
          {:error, :eio}
        end)
      )

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :storage, :accounting, :updated],
          fn _event, _measurements, metadata, _config ->
            if metadata.action == :released and metadata.workspace_id == project.workspace_id do
              before_cancel = Repo.get!(ProjectSnapshot, requested.id)

              assert {:ok, cancellation_requested} =
                       Versioning.cancel_project_snapshot(scope, project, requested.id)

              send(
                parent,
                {:retry_cancel_won, before_cancel.lifecycle_generation, cancellation_requested.lifecycle_generation}
              )
            end
          end,
          nil
        )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        Application.put_env(:storyarn, :storage, original_storage_config)
      end)

      assert {:ok, %ProjectSnapshot{lifecycle_state: "cancelled"}} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 2
               )

      assert_receive {:retry_cancel_won, generation_before_cancel, generation_after_cancel}
      assert generation_after_cancel == generation_before_cancel + 1

      cancelled = Repo.get!(ProjectSnapshot, requested.id)
      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.lifecycle_generation == generation_after_cancel
      assert cancelled.cancel_requested_at
      assert cancelled.cancelled_at
      refute Repo.get(ProjectSnapshotCapture, cancelled.id)

      reservations =
        Repo.all(
          from(reservation in StorageReservation,
            where:
              reservation.project_snapshot_id_snapshot == ^requested.id and
                reservation.kind == "snapshot_build"
          )
        )

      assert [%StorageReservation{id: reservation_id, status: "released"}] = reservations
      assert reservation_id == requested.storage_reservation_id
      assert cancelled.storage_reservation_id == reservation_id
    end

    test "exhausts cleanup ownership retries and leaves exact recovery authority" do
      user = user_fixture()
      project = project_fixture(user)
      _asset = upload_asset!(project, user, "ambiguous cleanup source")
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      job = requested_job(requested)
      original_storage_config = Application.get_env(:storyarn, :storage, [])
      original_snapshot_config = Application.get_env(:storyarn, SnapshotArchiveStorage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :put_if_absent_file_write, fn _path, _data ->
          {:error, :eio}
        end)
      )

      Application.put_env(
        :storyarn,
        SnapshotArchiveStorage,
        Keyword.put(original_snapshot_config, :cleanup_persist_fun, fn _keys ->
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, :storage, original_storage_config)
        Application.put_env(:storyarn, SnapshotArchiveStorage, original_snapshot_config)
      end)

      assert {:retry, :cleanup_unowned} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 5
               )

      still_building = Repo.get!(ProjectSnapshot, requested.id)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)

      assert still_building.lifecycle_state == "building"
      assert is_nil(still_building.failure_code)
      assert still_building.build_attempt == 1
      assert still_building.storage_reservation_id == requested.storage_reservation_id
      assert reservation.status == "active"
      assert reservation.storage_started_at

      assert {:discard, :cleanup_unowned} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 5,
                 max_attempts: 5
               )

      failed = Repo.get!(ProjectSnapshot, requested.id)
      assert failed.lifecycle_state == "failed"
      assert failed.failure_code == "cleanup_unowned"
      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      assert {:ok, intent} = recover_expired_build!(failed, reservation.id)
      assert intent.reason == "expired_build"
      refute Repo.get(ProjectSnapshot, failed.id)
      assert Repo.get!(StorageReservation, reservation.id).status == "released"
    end

    test "duplicate delivery snoozes for an active writer and resumes its empty namespace after lease expiry" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      capture = Repo.get!(ProjectSnapshotCapture, requested.id)
      job = requested_job(requested)

      inventory_digest =
        SnapshotObjectPublicationClaim.inventory_digest(%{
          format_version: requested.format_version,
          mode: requested.mode,
          object_prefix: requested.object_prefix,
          archive_storage_key: requested.archive_storage_key,
          archive_size_bytes: requested.archive_size_bytes,
          manifest_storage_key: requested.manifest_storage_key,
          manifest_size_bytes: requested.manifest_size_bytes,
          manifest_checksum: requested.manifest_checksum,
          project_size_bytes: requested.project_size_bytes,
          project_checksum: requested.project_checksum,
          total_size_bytes: requested.total_size_bytes,
          accounted_size_bytes: requested.total_size_bytes,
          asset_blob_size_bytes: capture.asset_blob_size_bytes,
          accounting_version: 1,
          object_count: requested.object_count,
          asset_count: requested.asset_count,
          blob_count: requested.blob_count,
          capture_digest: requested.capture_digest
        })

      claim =
        requested.object_prefix
        |> SnapshotObjectPublicationClaim.create_changeset(
          inventory_digest,
          Ecto.UUID.generate(),
          DateTime.add(TimeHelpers.now(), 3_600, :second),
          reservation.id,
          reservation.lease_token
        )
        |> Repo.insert!()

      assert {:snooze, 30} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 5
               )

      building = Repo.get!(ProjectSnapshot, requested.id)
      unchanged_reservation = Repo.get!(StorageReservation, reservation.id)

      assert building.lifecycle_state == "building"
      assert is_nil(building.failure_code)
      assert unchanged_reservation.status == "active"
      assert is_nil(unchanged_reservation.storage_started_at)
      assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == "staging"

      expired_at = DateTime.add(TimeHelpers.now(), -1, :second)

      claim
      |> SnapshotObjectPublicationClaim.status_changeset("staging", expired_at)
      |> Repo.update!()

      assert {:ok, %ProjectSnapshot{lifecycle_state: "ready"} = ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 5,
                 max_attempts: 5
               )

      assert ready.id == requested.id
      assert ready.integrity_state == "verified"
      assert ready.progress_phase == "complete"
      assert Repo.get!(StorageReservation, reservation.id).status == "committed"
      assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == "published"
    end

    test "retry recovers a complete staging pair after its publication lease expires" do
      user = user_fixture()
      project = project_fixture(user)
      _asset = upload_asset!(project, user, "started staging crash")
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      capture = Repo.get!(ProjectSnapshotCapture, requested.id)
      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)
      job = requested_job(requested)
      prepared = prepared_archive_capture(requested, capture)
      token = List.last(String.split(requested.object_prefix, "/"))

      assert {:ok, staged} =
               SnapshotArchiveStorage.stage_prepared(
                 requested.project_id,
                 prepared,
                 token: token,
                 storage_reservation: reservation,
                 before_stage: fn staged ->
                   assert {:ok, _snapshot} =
                            requested
                            |> ProjectSnapshot.build_state_changeset(%{
                              publication_claim_token: staged.publication_claim_token,
                              state_updated_at: TimeHelpers.now()
                            })
                            |> Repo.update()

                   current_reservation = Repo.get!(StorageReservation, reservation.id)

                   Billing.mark_storage_reservation_started(
                     current_reservation.id,
                     current_reservation.lease_token,
                     current_reservation.generation,
                     staged.cleanup
                   )
                 end
               )

      claim = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)
      Repo.delete!(claim)

      Repo.insert!(%SnapshotObjectPublicationClaim{
        object_prefix: claim.object_prefix,
        claim_token: claim.claim_token,
        inventory_digest: claim.inventory_digest,
        storage_reservation_id_snapshot: claim.storage_reservation_id_snapshot,
        storage_reservation_lease_token: claim.storage_reservation_lease_token,
        status: "staging",
        lease_expires_at: DateTime.add(TimeHelpers.now(), -1, :second)
      })

      assert {:ok, %ProjectSnapshot{lifecycle_state: "ready"} = ready} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 2,
                 max_attempts: 5
               )

      assert ready.integrity_state == "verified"
      assert ready.archive_checksum == staged.archive_checksum
      assert Repo.get!(StorageReservation, reservation.id).status == "committed"
      assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == "published"
    end

    test "a foreign build-job delivery is discarded without touching its owner's reservation" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)

      assert {:ok, foreign_job} =
               %{snapshot_id: requested.id, delivery: Ecto.UUID.generate()}
               |> BuildProjectSnapshotWorker.new(queue: :snapshot_archives)
               |> Oban.insert()

      assert foreign_job.queue == "snapshot_archives"

      assert {:discard, :snapshot_build_owned_by_another_job} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: foreign_job.id,
                 attempt: 1,
                 max_attempts: 5
               )

      assert Repo.get!(ProjectSnapshot, requested.id).build_job_id == requested.build_job_id
      assert Repo.get!(StorageReservation, requested.storage_reservation_id).status == "active"
    end

    test "releases an unstarted orphan reservation when its project is deleted before claim" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      job = requested_job(requested)

      Repo.delete!(project)

      assert {:discard, :project_snapshot_not_found} =
               Versioning.perform_project_snapshot_build(requested.id,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1
               )

      refute Repo.get(ProjectSnapshot, requested.id)

      orphaned = Repo.get!(StorageReservation, requested.storage_reservation_id)
      assert orphaned.status == "released"
      assert orphaned.cleanup_status == "not_required"
      assert orphaned.workspace_id
      assert is_nil(orphaned.project_id)
      assert is_nil(orphaned.project_snapshot_id)
    end
  end

  describe "cancel_project_snapshot/3" do
    test "atomically cancels an unstarted build and releases its reservation" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      assert :ok = Versioning.subscribe_project_snapshots(project.id)

      cancelled = cancel_snapshot!(user, project, requested)

      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == requested.id

      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.cancel_requested_at
      assert cancelled.cancelled_at
      assert Repo.get!(StorageReservation, cancelled.storage_reservation_id).status == "released"

      assert :ok = perform_requested_job(cancelled)
      assert Repo.get!(ProjectSnapshot, cancelled.id).lifecycle_state == "cancelled"
    end

    test "cancellation exhausts active-writer retries and becomes recoverable" do
      for claim_status <- ["staging", "publishing"] do
        user = user_fixture()
        project = project_fixture(user)
        assert {:ok, requested} = request_snapshot(user, project)

        {reservation, _cleanup_scope, claim, _capture} =
          start_snapshot_storage!(project, requested, claim_status)

        cancellation_requested = cancel_snapshot!(user, project, requested)

        assert {:error, :cleanup_unowned} = perform_requested_job(cancellation_requested)
        assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == claim_status
        assert_active_cancellation_fence(requested.id, reservation.id)

        assert {:discard, :cleanup_unowned} = perform_requested_job(cancellation_requested, 3)

        failed = Repo.get!(ProjectSnapshot, requested.id)
        assert failed.lifecycle_state == "failed"
        assert failed.failure_code == "cleanup_unowned"
        assert Repo.get!(StorageReservation, reservation.id).status == "active"
        refute Repo.get(ProjectSnapshotCapture, failed.id)

        assert {:ok, intent} = recover_expired_build!(failed, reservation.id)
        assert intent.reason == "expired_build"
        refute Repo.get(ProjectSnapshot, failed.id)
        assert Repo.get!(StorageReservation, reservation.id).status == "released"
      end
    end

    test "cancellation after storage starts reconstructs and owns the exact cleanup inventory" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)
      requested = Repo.get!(ProjectSnapshot, requested.id)

      assert cleanup_scope.estimated_cleanup_bytes ==
               2 * (requested.archive_size_bytes + requested.manifest_size_bytes)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      assert cancellation_requested.lifecycle_state == "pending"
      assert cancellation_requested.cancel_requested_at

      handler_id = "snapshot-cancel-cleanup-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :assets, :storage_compensation, :fallback_persisted],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = perform_requested_job(cancellation_requested)
      refute_receive {[:storyarn, :assets, :storage_compensation, :fallback_persisted], _, _}

      cancelled = Repo.get!(ProjectSnapshot, requested.id)
      released = Repo.get!(StorageReservation, reservation.id)
      claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)

      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.cancelled_at
      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert claim.status == "poisoned"
      refute Repo.get(ProjectSnapshotCapture, cancelled.id)

      assert "storage_cleanup_request:" <> cleanup_request_id = released.cleanup_reference
      cleanup_request = Repo.get!(StorageCleanupRequest, String.to_integer(cleanup_request_id))

      assert MapSet.equal?(
               MapSet.new(cleanup_request.storage_keys),
               MapSet.new(cleanup_scope.storage_keys)
             )
    end

    test "cancellation keeps its reservation active until cleanup ownership can be persisted" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, _cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :cancel_cleanup_persist_fun, fn _keys ->
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      assert {:error, :cleanup_unowned} = perform_requested_job(cancellation_requested)

      still_cancelling = Repo.get!(ProjectSnapshot, requested.id)
      active_reservation = Repo.get!(StorageReservation, reservation.id)
      poisoned_claim = Repo.get!(SnapshotObjectPublicationClaim, requested.object_prefix)

      assert still_cancelling.lifecycle_state == "building"
      assert still_cancelling.cancel_requested_at
      assert is_nil(still_cancelling.cancelled_at)
      assert active_reservation.status == "active"
      assert poisoned_claim.status == "poisoned"

      Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)

      assert :ok = perform_requested_job(still_cancelling)

      cancelled = Repo.get!(ProjectSnapshot, requested.id)
      released = Repo.get!(StorageReservation, reservation.id)

      assert cancelled.lifecycle_state == "cancelled"
      assert cancelled.cancelled_at
      assert released.status == "released"
      assert released.cleanup_status == "owned"
    end

    test "cancellation reuses an immutable cleanup receipt after release fails and the cleanup remains consumable" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      parent = self()

      persist_once = fn storage_keys ->
        assert {:ok, cleanup_request} =
                 StorageCompensation.persist_planned_cleanup_request(storage_keys)

        send(parent, {:cleanup_persisted, cleanup_request.id})
        {:ok, %{id: cleanup_request.id + 1_000_000}}
      end

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :cancel_cleanup_persist_fun, persist_once)
      )

      on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original_config) end)

      assert {:error, :cleanup_unowned} = perform_requested_job(cancellation_requested)
      assert_receive {:cleanup_persisted, cleanup_request_id}
      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :cancel_cleanup_persist_fun, fn _keys ->
          flunk("an immutable ownership receipt must prevent a duplicate cleanup request")
        end)
      )

      assert :ok = perform_requested_job(Repo.get!(ProjectSnapshot, requested.id))

      released = Repo.get!(StorageReservation, reservation.id)
      assert released.status == "released"
      assert released.cleanup_reference == "storage_cleanup_request:#{cleanup_request_id}"

      assert Repo.aggregate(
               from(request in StorageCleanupRequest,
                 where: request.storage_keys == ^Enum.sort(cleanup_scope.storage_keys)
               ),
               :count,
               :id
             ) == 1

      assert :ok =
               RetryStorageCleanupRequestsWorker.perform(%Oban.Job{
                 args: %{},
                 attempt: 1,
                 max_attempts: 5
               })

      assert %StorageCleanupRequest{
               multipart_quiescence_started_at: %DateTime{},
               multipart_quiescence_not_before: %DateTime{}
             } = Repo.get!(StorageCleanupRequest, cleanup_request_id)

      now = TimeHelpers.now()

      cleanup_request_id
      |> then(&Repo.get!(StorageCleanupRequest, &1))
      |> Ecto.Changeset.change(
        multipart_quiescence_started_at: DateTime.add(now, -2, :second),
        multipart_quiescence_not_before: DateTime.add(now, -1, :second)
      )
      |> Repo.update!()

      assert :ok =
               RetryStorageCleanupRequestsWorker.perform(%Oban.Job{
                 args: %{},
                 attempt: 1,
                 max_attempts: 5
               })

      refute Repo.get(StorageCleanupRequest, cleanup_request_id)
    end

    test "terminal persistence failure leaves a reconcilable release and emits accounting only once" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project)
      {reservation, _cleanup_scope, _claim, _capture} = start_snapshot_storage!(project, requested)

      cancellation_requested = cancel_snapshot!(user, project, requested)

      original_config = Application.get_env(:storyarn, ProjectSnapshotBuild, [])
      handler_id = "snapshot-terminal-persist-#{System.unique_integer([:positive])}"
      parent = self()

      :ok = Versioning.subscribe_project_snapshots(project.id)

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :storage, :accounting, :updated],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      Application.put_env(
        :storyarn,
        ProjectSnapshotBuild,
        Keyword.put(original_config, :terminal_state_persist_fun, fn _changeset ->
          {:error, :database_unavailable}
        end)
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
        Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)
      end)

      assert {:error, :snapshot_build_cancel_state_persist_failed} =
               perform_requested_job(cancellation_requested)

      assert %ProjectSnapshot{lifecycle_state: "building", cancelled_at: nil} =
               Repo.get!(ProjectSnapshot, requested.id)

      assert %StorageReservation{status: "released", cleanup_status: "owned"} =
               Repo.get!(StorageReservation, reservation.id)

      assert_receive {
        [:storyarn, :storage, :accounting, :updated],
        _measurements,
        %{workspace_id: workspace_id, action: :released}
      }

      assert workspace_id == project.workspace_id
      refute_receive {:project_snapshot_updated, _snapshot_id}
      refute_receive :notifications_changed
      assert Notifications.list_notifications(scope) == []

      Application.put_env(:storyarn, ProjectSnapshotBuild, original_config)

      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "scheduled",
        scheduled_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 1} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert %ProjectSnapshot{lifecycle_state: "cancelled", cancelled_at: %DateTime{}} =
               Repo.get!(ProjectSnapshot, requested.id)

      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == requested.id
      refute_receive {[:storyarn, :storage, :accounting, :updated], _, _}
      refute_receive :notifications_changed
      assert Notifications.list_notifications(scope) == []
    end

    test "reconciliation terminalizes a pending build released before capture persistence" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project, %{title: "Recovered failure"})

      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)

      assert {:ok, %StorageReservation{status: "released"}} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "build_failed",
                   cleanup_status: "not_required",
                   cleanup_proof: %{
                     type: "storage_not_started",
                     storage_namespace: reservation.storage_namespace
                   }
                 }
               )

      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "discarded",
        discarded_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

      refute_receive :notifications_changed
      assert Notifications.list_notifications(scope) == []

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 1} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert_receive :notifications_changed

      assert %ProjectSnapshot{
               lifecycle_state: "failed",
               integrity_state: "incomplete",
               progress_phase: "failed",
               failure_code: "build_failed",
               failed_at: %DateTime{}
             } = Repo.get!(ProjectSnapshot, requested.id)

      refute Repo.get(ProjectSnapshotCapture, requested.id)
      assert_snapshot_notification(scope, requested, "failure", "Recovered failure")
    end

    test "reconciliation terminalizes a released build after Oban prunes its job" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)

      :ok = Notifications.subscribe(scope)
      assert {:ok, requested} = request_snapshot(user, project, %{title: "Pruned job failure"})

      reservation = Repo.get!(StorageReservation, requested.storage_reservation_id)

      assert {:ok, %StorageReservation{status: "released"}} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "build_failed",
                   cleanup_status: "not_required",
                   cleanup_proof: %{
                     type: "storage_not_started",
                     storage_namespace: reservation.storage_namespace
                   }
                 }
               )

      job_id = requested.build_job_id
      job_id |> then(&Repo.get!(Oban.Job, &1)) |> Repo.delete!()

      refute Repo.get(Oban.Job, job_id)

      assert %ProjectSnapshot{build_job_id: ^job_id, lifecycle_state: "pending"} =
               Repo.get!(ProjectSnapshot, requested.id)

      refute_receive :notifications_changed
      assert Notifications.list_notifications(scope) == []

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 1} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert_receive :notifications_changed
      refute_receive :notifications_changed

      assert %ProjectSnapshot{
               build_job_id: ^job_id,
               lifecycle_state: "failed",
               integrity_state: "incomplete",
               progress_phase: "failed",
               failure_code: "build_failed",
               failed_at: %DateTime{}
             } = Repo.get!(ProjectSnapshot, requested.id)

      assert_snapshot_notification(scope, requested, "failure", "Pruned job failure")

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      refute_receive :notifications_changed
      assert_snapshot_notification(scope, requested, "failure", "Pruned job failure")
    end

    test "rejects callers without project management permission" do
      owner = user_fixture()
      unauthorized_user = user_fixture()
      project = project_fixture(owner)
      assert {:ok, requested} = request_snapshot(owner, project)

      assert {:error, :unauthorized} =
               Versioning.cancel_project_snapshot(
                 user_scope_fixture(unauthorized_user),
                 project,
                 requested.id
               )

      unchanged = Repo.get!(ProjectSnapshot, requested.id)
      assert unchanged.lifecycle_state == "pending"
      assert is_nil(unchanged.cancel_requested_at)
      assert Repo.get!(StorageReservation, unchanged.storage_reservation_id).status == "active"
    end

    test "rejects cancellation after final publication authorization" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      now = TimeHelpers.now()

      building =
        requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      finalizing =
        building
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "verifying",
          progress_phase: "finalizing",
          verifying_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      assert {:error, :snapshot_finalization_in_progress} =
               Versioning.cancel_project_snapshot(user_scope_fixture(user), project, finalizing.id)

      unchanged = Repo.get!(ProjectSnapshot, finalizing.id)
      assert unchanged.progress_phase == "finalizing"
      assert is_nil(unchanged.cancel_requested_at)
      assert Repo.get!(StorageReservation, unchanged.storage_reservation_id).status == "active"
    end

    test "redelivering an accepted cancellation remains idempotent during finalizing" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      requested = materialize_snapshot_capture!(requested)
      now = TimeHelpers.now()

      building =
        requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      cancellation_requested =
        building
        |> ProjectSnapshot.cancel_request_changeset(now)
        |> Repo.update!()

      finalizing =
        cancellation_requested
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "verifying",
          progress_phase: "finalizing",
          verifying_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      assert {:ok, idempotent} =
               Versioning.cancel_project_snapshot(user_scope_fixture(user), project, finalizing.id)

      assert idempotent.id == finalizing.id
      assert idempotent.cancel_requested_at == finalizing.cancel_requested_at
      assert idempotent.lifecycle_generation == finalizing.lifecycle_generation
    end
  end

  defp assert_active_cancellation_fence(snapshot_id, reservation_id) do
    snapshot = Repo.get!(ProjectSnapshot, snapshot_id)
    reservation = Repo.get!(StorageReservation, reservation_id)

    assert snapshot.lifecycle_state == "building"
    assert snapshot.cancel_requested_at
    assert is_nil(snapshot.cancelled_at)
    assert reservation.status == "active"
    assert is_nil(reservation.cleanup_status)
    assert is_nil(reservation.cleanup_reference)
  end

  defp start_snapshot_storage!(_project, snapshot, claim_status \\ "poisoned") do
    snapshot = materialize_snapshot_capture!(snapshot)
    reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
    capture = Repo.get!(ProjectSnapshotCapture, snapshot.id)

    assert {:ok, cleanup_scope} = SnapshotArchiveStorage.cleanup_scope_from_snapshot(snapshot)

    assert {:ok, started} =
             Billing.mark_storage_reservation_started(
               reservation.id,
               reservation.lease_token,
               reservation.generation,
               cleanup_scope
             )

    claim =
      snapshot.object_prefix
      |> SnapshotObjectPublicationClaim.create_changeset(
        String.duplicate("a", 64),
        Ecto.UUID.generate(),
        DateTime.add(TimeHelpers.now(), 3_600, :second),
        started.id,
        started.lease_token
      )
      |> Repo.insert!()

    claim = transition_publication_claim!(claim, claim_status)

    {started, cleanup_scope, claim, capture}
  end

  defp sheet_without_flow_node_id(project) do
    sheet = Storyarn.SheetsFixtures.sheet_fixture(project)

    if Repo.get(FlowNode, sheet.id),
      do: sheet_without_flow_node_id(project),
      else: sheet
  end

  defp localized_text_snapshot(text) do
    fields = [
      :source_type,
      :source_id,
      :source_field,
      :source_text,
      :source_text_hash,
      :translated_source_hash,
      :locale_code,
      :translated_text,
      :status,
      :vo_status,
      :vo_asset_id,
      :translator_notes,
      :reviewer_notes,
      :speaker_sheet_id,
      :word_count,
      :content_role,
      :vo_eligible,
      :machine_translated,
      :last_translated_at,
      :last_reviewed_at,
      :translated_by_id,
      :reviewed_by_id,
      :archived_at,
      :archive_reason
    ]

    text
    |> Map.from_struct()
    |> Map.take(fields)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp request_snapshot(user, project, attrs \\ %{}) do
    request_attrs = Map.put(attrs, :idempotency_key, Ecto.UUID.generate())
    Versioning.request_full_project_snapshot(user_scope_fixture(user), project, request_attrs)
  end

  defp assert_snapshot_notification(scope, snapshot, status, entity_name) do
    assert [notification] = Notifications.list_notifications(scope)
    assert notification.recipient_id == scope.user.id
    assert is_nil(notification.actor_id)
    assert notification.project_id == snapshot.project_id
    assert notification.kind == "async_operation"
    assert notification.entity_type == "project_snapshot"
    assert notification.entity_id == snapshot.id
    assert notification.entity_name == entity_name
    assert notification.status == status
    assert notification.dedupe_key == "project_snapshot:#{snapshot.id}:#{status}"
    notification
  end

  defp materialize_snapshot_capture!(snapshot) do
    job = requested_job(snapshot)

    assert {:ok, state} = ProjectSnapshotBuild.materialize_capture(snapshot.id, job.id)
    assert state in [:captured, :already_captured]

    Repo.get!(ProjectSnapshot, snapshot.id)
  end

  defp prepared_archive_capture(snapshot, capture) do
    %{
      capture_digest: capture.capture_digest,
      project_json: capture.project_json,
      manifest_json: capture.manifest_json,
      source_keys: capture.source_keys,
      project_size_bytes: capture.project_size_bytes,
      project_checksum: snapshot.project_checksum,
      manifest_size_bytes: capture.manifest_size_bytes,
      manifest_checksum: snapshot.manifest_checksum,
      total_size_bytes: capture.total_size_bytes,
      asset_blob_size_bytes: capture.asset_blob_size_bytes,
      object_count: capture.object_count,
      asset_count: capture.asset_count,
      blob_count: capture.blob_count
    }
  end

  defp cancel_snapshot!(user, project, snapshot) do
    assert {:ok, cancelled} =
             Versioning.cancel_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    cancelled
  end

  defp transition_publication_claim!(claim, "staging"), do: claim

  defp transition_publication_claim!(claim, "publishing") do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset("staged")
    |> Repo.update!()
    |> SnapshotObjectPublicationClaim.status_changeset(
      "publishing",
      DateTime.add(TimeHelpers.now(), 3_600, :second)
    )
    |> Repo.update!()
  end

  defp transition_publication_claim!(claim, status) do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset(status)
    |> Repo.update!()
  end

  defp perform_requested_job(snapshot, attempt \\ 1) do
    snapshot
    |> requested_job()
    |> Map.put(:attempt, attempt)
    |> Map.put(:errors, List.duplicate(%{}, max(attempt - 1, 0)))
    |> BuildProjectSnapshotWorker.perform()
  end

  defp recover_expired_build!(snapshot, reservation_id) do
    now = TimeHelpers.now()
    expired_at = DateTime.add(now, -1, :second)

    quiesced_at =
      now
      |> DateTime.add(-Versioning.project_snapshot_build_recovery_quarantine_seconds() - 1, :second)
      |> Map.put(:microsecond, {0, 6})

    reservation_id
    |> then(&Repo.get!(StorageReservation, &1))
    |> Ecto.Changeset.change(
      expires_at: expired_at,
      accounting_measured_at: DateTime.add(expired_at, -1, :second)
    )
    |> Repo.update!()

    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(state: "discarded", discarded_at: quiesced_at)
    |> Repo.update!()

    assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)
    Versioning.delete_expired_project_snapshot_build_candidate(candidate)
  end

  defp requested_job(snapshot) do
    snapshot.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> case do
      %Oban.Job{state: "executing"} = job ->
        job

      %Oban.Job{} = job ->
        job
        |> Ecto.Changeset.change(
          state: "executing",
          attempt: max(job.attempt, 1),
          attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
        )
        |> Repo.update!()
    end
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp set_stale_build_heartbeat_seconds(seconds) do
    original = Application.fetch_env!(:storyarn, :snapshot_lifecycle)

    Application.put_env(
      :storyarn,
      :snapshot_lifecycle,
      Keyword.put(original, :stale_build_heartbeat_seconds, seconds)
    )

    on_exit(fn -> Application.put_env(:storyarn, :snapshot_lifecycle, original) end)
  end

  defp upload_asset!(project, user, contents) do
    assert {:ok, asset} =
             Assets.upload_binary_and_create_asset(
               contents,
               %{filename: "snapshot.png", content_type: "image/png"},
               project,
               user
             )

    asset
  end

  defp protected_blob_key(project_id, asset) do
    BlobStore.blob_key(project_id, asset.blob_hash, BlobStore.ext_from_content_type(asset.content_type))
  end
end
