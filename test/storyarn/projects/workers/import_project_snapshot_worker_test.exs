defmodule Storyarn.Workers.ImportProjectSnapshotWorkerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Workers.ImportProjectSnapshotWorker

  setup do
    handler_id = "workspace-snapshot-import-delivery-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :snapshot, :import, :delivery, :stop],
        fn event, measurements, metadata, pid ->
          send(pid, {event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    %{job: %Oban.Job{id: 42, args: %{"import_id" => 7}, attempt: 1, max_attempts: 3}}
  end

  test "collapses retry details before returning them to Oban", %{job: job} do
    private_value = "author@example.com/private-project.zip?signature=secret"

    changeset =
      Ecto.Changeset.change(%WorkspaceSnapshotImport{
        original_filename: private_value,
        project_name: private_value,
        archive_storage_key: private_value
      })

    result =
      ImportProjectSnapshotWorker.perform_import(job, fn 7, _opts ->
        {:retry, {:workspace_snapshot_import_retry_state_failed, changeset}}
      end)

    assert result == {:error, :workspace_snapshot_import_retry}
    refute inspect(result) =~ private_value

    assert_receive {
      [:storyarn, :snapshot, :import, :delivery, :stop],
      %{count: 1},
      %{outcome: :retrying}
    }
  end

  test "collapses discard details before returning them to Oban", %{job: job} do
    private_value = "writer@example.com/private-project-name"

    result =
      ImportProjectSnapshotWorker.perform_import(job, fn 7, _opts ->
        {:discard, {:provider_rejected, private_value}}
      end)

    assert result == {:discard, :workspace_snapshot_import_discarded}
    refute inspect(result) =~ private_value

    assert_receive {
      [:storyarn, :snapshot, :import, :delivery, :stop],
      %{count: 1},
      %{outcome: :discarded}
    }
  end

  test "rejects malformed snoozes without returning callback data", %{job: job} do
    private_value = "author@example.com/private-project.zip"

    result =
      ImportProjectSnapshotWorker.perform_import(job, fn 7, _opts ->
        {:snooze, private_value}
      end)

    assert result == {:error, :workspace_snapshot_import_unexpected_result}
    refute inspect(result) =~ private_value

    assert_receive {
      [:storyarn, :snapshot, :import, :delivery, :stop],
      %{count: 1},
      %{outcome: :unexpected}
    }
  end

  test "collapses exception messages in logs and returned errors", %{job: job} do
    private_value = "author@example.com/private-project.zip?signature=secret"

    {result, log} =
      with_log(fn ->
        ImportProjectSnapshotWorker.perform_import(job, fn 7, _opts -> raise private_value end)
      end)

    assert result == {:error, :workspace_snapshot_import_delivery_failed}
    refute inspect(result) =~ private_value
    assert log =~ "failure=exception"
    assert log =~ "exception_module=RuntimeError"
    refute log =~ private_value

    assert_receive {
      [:storyarn, :snapshot, :import, :delivery, :stop],
      %{count: 1},
      %{outcome: :unexpected}
    }
  end

  test "emits an unexpected outcome for malformed private job arguments" do
    private_value = "author@example.com/private-project.zip?signature=secret"

    result =
      ImportProjectSnapshotWorker.perform_import(
        %Oban.Job{args: %{"invalid" => private_value}},
        fn _import_id, _opts -> flunk("malformed jobs must not invoke the domain callback") end
      )

    assert result == {:discard, :invalid_workspace_snapshot_import_job}
    refute inspect(result) =~ private_value

    assert_receive {
      [:storyarn, :snapshot, :import, :delivery, :stop],
      %{count: 1},
      %{outcome: :unexpected}
    }
  end
end
