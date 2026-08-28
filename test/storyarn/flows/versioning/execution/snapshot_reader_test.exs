defmodule Storyarn.Flows.Versioning.Execution.SnapshotReaderTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.Execution.SnapshotReader
  alias Storyarn.Flows.Versioning.SnapshotStorage

  test "accepts only the storage key owned by the version identity" do
    version = version_record(11, 22, 3)

    assert :ok = SnapshotReader.validate_storage_key(version)

    for forged <- [
          %{version | storage_key: version_record(12, 22, 3).storage_key},
          %{version | storage_key: version_record(11, 23, 3).storage_key},
          %{version | storage_key: version_record(11, 22, 4).storage_key},
          %{version | storage_key: nil}
        ] do
      assert {:error, :entity_version_storage_key_mismatch} =
               SnapshotReader.validate_storage_key(forged)
    end
  end

  defp version_record(project_id, flow_id, version_number) do
    %EntityVersionRecord{
      project_id: project_id,
      entity_id: flow_id,
      version_number: version_number,
      storage_key: SnapshotStorage.build_key(project_id, flow_id, version_number, "0123456789abcdef")
    }
  end
end
