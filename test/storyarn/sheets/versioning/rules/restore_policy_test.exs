defmodule Storyarn.Sheets.Versioning.RestorePolicyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Versioning.RestorePolicy

  test "builder access requires the policy-scoped Sheet restore action" do
    assert :ok = RestorePolicy.ensure_builder_enabled("sheet", {:entity_version_restore, "sheet"})

    assert {:error, :restore_temporarily_disabled} = RestorePolicy.ensure_builder_enabled("sheet", nil)

    assert {:error, :restore_temporarily_disabled} =
             RestorePolicy.ensure_builder_enabled("scene", {:entity_version_restore, "sheet"})

    assert {:error, :restore_temporarily_disabled} =
             RestorePolicy.ensure_builder_enabled("sheet", {:entity_version_restore, "scene"})
  end
end
