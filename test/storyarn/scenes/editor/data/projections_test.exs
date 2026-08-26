defmodule Storyarn.Scenes.Editor.Data.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Editor.Data.AssetRecord
  alias Storyarn.Scenes.Editor.Data.EntityVersionRecord
  alias Storyarn.Scenes.Editor.Data.FlowRecord
  alias Storyarn.Scenes.Editor.Data.ProjectRecord
  alias Storyarn.Scenes.Editor.Data.SheetRecord
  alias Storyarn.Scenes.Editor.Data.WorkspaceRecord
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone

  test "editor entities associate only to editor-owned foreign projections" do
    assert association(Scene, :project) == ProjectRecord
    assert association(Scene, :background_asset) == AssetRecord
    assert association(Scene, :current_version) == EntityVersionRecord

    assert association(ScenePin, :sheet) == SheetRecord
    assert association(ScenePin, :flow) == FlowRecord
    assert association(ScenePin, :icon_asset) == AssetRecord
    assert association(SceneZone, :label_icon_asset) == AssetRecord
    assert association(ProjectRecord, :workspace) == WorkspaceRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
