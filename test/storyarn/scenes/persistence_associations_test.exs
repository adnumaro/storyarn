defmodule Storyarn.Scenes.PersistenceAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.ExplorationSession
  alias Storyarn.Scenes.Persistence.AssetRecord
  alias Storyarn.Scenes.Persistence.FlowRecord
  alias Storyarn.Scenes.Persistence.ProjectRecord
  alias Storyarn.Scenes.Persistence.SheetRecord
  alias Storyarn.Scenes.Persistence.UserRecord
  alias Storyarn.Scenes.Persistence.WorkspaceRecord
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.Versioning.EntityVersionRecord

  test "Scene schemas associate only to context-owned persistence records" do
    assert association(Scene, :project) == ProjectRecord
    assert association(Scene, :background_asset) == AssetRecord
    assert association(Scene, :current_version) == EntityVersionRecord

    assert association(ScenePin, :sheet) == SheetRecord
    assert association(ScenePin, :flow) == FlowRecord
    assert association(ScenePin, :icon_asset) == AssetRecord
    assert association(SceneZone, :label_icon_asset) == AssetRecord

    assert association(ExplorationSession, :project) == ProjectRecord
    assert association(ExplorationSession, :user) == UserRecord
    assert association(EntityVersionRecord, :project) == ProjectRecord
    assert association(EntityVersionRecord, :created_by) == UserRecord
    assert association(ProjectRecord, :workspace) == WorkspaceRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
