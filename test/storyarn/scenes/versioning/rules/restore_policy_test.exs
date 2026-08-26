defmodule Storyarn.Scenes.Versioning.Rules.RestorePolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Versioning.RestorePolicy

  test "builder access requires the policy-scoped Scene restore action" do
    assert :ok = RestorePolicy.ensure_builder_enabled("scene", {:entity_version_restore, "scene"})

    assert {:error, :restore_temporarily_disabled} = RestorePolicy.ensure_builder_enabled("scene", nil)

    assert {:error, :restore_temporarily_disabled} =
             RestorePolicy.ensure_builder_enabled("sheet", {:entity_version_restore, "scene"})

    assert {:error, :restore_temporarily_disabled} =
             RestorePolicy.ensure_builder_enabled("scene", {:entity_version_restore, "sheet"})
  end
end
