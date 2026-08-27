defmodule Storyarn.Flows.Versioning.Rules.RestorePolicyTest do
  use ExUnit.Case, async: false

  alias Storyarn.Flows.Versioning.RestorePolicy

  setup do
    original_config = Application.get_env(:storyarn, RestorePolicy)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, original_config)
      end
    end)
  end

  test "only literal true enables the policy-scoped Flow restore action" do
    Application.put_env(:storyarn, RestorePolicy, flow_version_restore: true)

    assert RestorePolicy.enabled?({:entity_version_restore, "flow"})
    assert :ok = RestorePolicy.ensure_enabled({:entity_version_restore, "flow"})
    refute RestorePolicy.enabled?({:entity_version_restore, "sheet"})
    refute RestorePolicy.enabled?(:unknown_action)
  end

  test "missing and malformed configuration fails closed" do
    invalid_configs = [nil, %{}, "true", 1, ["invalid"], [], [flow_version_restore: "true"], [flow_version_restore: 1]]

    for invalid_config <- invalid_configs do
      if is_nil(invalid_config) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, invalid_config)
      end

      refute RestorePolicy.enabled?({:entity_version_restore, "flow"})

      assert {:error, :restore_temporarily_disabled} =
               RestorePolicy.ensure_enabled({:entity_version_restore, "flow"})
    end
  end
end
