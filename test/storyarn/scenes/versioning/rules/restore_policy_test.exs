defmodule Storyarn.Scenes.Versioning.Rules.RestorePolicyTest do
  use ExUnit.Case, async: false

  alias Storyarn.Scenes.Versioning.RestorePolicy

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

  test "builder access requires the policy-scoped Scene restore action" do
    Application.put_env(:storyarn, RestorePolicy, scene_version_restore: true)

    assert :ok = RestorePolicy.ensure_builder_enabled("scene", {:entity_version_restore, "scene"})

    assert {:error, :restore_temporarily_disabled} = RestorePolicy.ensure_builder_enabled("scene", nil)

    assert {:error, :restore_temporarily_disabled} =
             RestorePolicy.ensure_builder_enabled("sheet", {:entity_version_restore, "scene"})

    assert {:error, :restore_temporarily_disabled} =
             RestorePolicy.ensure_builder_enabled("scene", {:entity_version_restore, "sheet"})
  end

  test "missing and malformed configuration fails closed" do
    invalid_configs = [nil, %{}, "true", 1, ["invalid"], [], [scene_version_restore: "true"], [scene_version_restore: 1]]

    for invalid_config <- invalid_configs do
      if is_nil(invalid_config) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, invalid_config)
      end

      refute RestorePolicy.enabled?()
      assert {:error, :restore_temporarily_disabled} = RestorePolicy.ensure_enabled()
    end
  end
end
