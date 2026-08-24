defmodule Storyarn.Projects.Versioning.RestorePolicyTest do
  use ExUnit.Case, async: false

  alias Storyarn.Projects.Versioning.RestorePolicy

  setup do
    original_config = Application.get_env(:storyarn, RestorePolicy)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, original_config)
      end
    end)

    :ok
  end

  test "exact full-project restore is always available" do
    Application.delete_env(:storyarn, RestorePolicy)

    assert RestorePolicy.enabled?({:project_snapshot_restore, "full"})
    assert :ok = RestorePolicy.ensure_enabled({:project_snapshot_restore, "full"})
  end

  test "every other restore action fails closed" do
    refute RestorePolicy.enabled?({:project_snapshot_restore, "partial"})
    refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?(:unknown_action)

    assert {:error, :restore_temporarily_disabled} = RestorePolicy.ensure_enabled(:unknown_action)
  end
end
