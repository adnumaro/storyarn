defmodule Storyarn.Architecture.ScenesProjectionAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Access.Projections.ProjectRecord, as: AccessProjectRecord
  alias Storyarn.Scenes.Access.Projections.WorkspaceRecord, as: AccessWorkspaceRecord
  alias Storyarn.Scenes.Assets.Projections.ProjectRecord, as: AssetsProjectRecord
  alias Storyarn.Scenes.Assets.Projections.WorkspaceRecord, as: AssetsWorkspaceRecord
  alias Storyarn.Scenes.Editor.Projections.AssetRecord, as: EditorAssetRecord
  alias Storyarn.Scenes.Editor.Projections.EntityVersionRecord, as: EditorVersionRecord
  alias Storyarn.Scenes.Editor.Projections.FlowRecord, as: EditorFlowRecord
  alias Storyarn.Scenes.Editor.Projections.ProjectRecord, as: EditorProjectRecord
  alias Storyarn.Scenes.Editor.Projections.SheetRecord, as: EditorSheetRecord
  alias Storyarn.Scenes.Exploration.Projections.AssetRecord, as: ExplorationAssetRecord
  alias Storyarn.Scenes.Exploration.Projections.ProjectRecord, as: ExplorationProjectRecord
  alias Storyarn.Scenes.Exploration.Projections.SheetAvatarRecord, as: ExplorationAvatarRecord
  alias Storyarn.Scenes.Exploration.Projections.SheetRecord, as: ExplorationSheetRecord
  alias Storyarn.Scenes.Exploration.Projections.UserRecord, as: ExplorationUserRecord
  alias Storyarn.Scenes.ExplorationSession
  alias Storyarn.Scenes.Health.Projections.AssetRecord, as: HealthAssetRecord
  alias Storyarn.Scenes.Health.Projections.BlockRecord, as: HealthBlockRecord
  alias Storyarn.Scenes.Health.Projections.SheetAvatarRecord, as: HealthAvatarRecord
  alias Storyarn.Scenes.Health.Projections.SheetRecord, as: HealthSheetRecord
  alias Storyarn.Scenes.References.Projections.AssetRecord, as: ReferencesAssetRecord
  alias Storyarn.Scenes.References.Projections.BlockRecord, as: ReferencesBlockRecord
  alias Storyarn.Scenes.References.Projections.ProjectRecord, as: ReferencesProjectRecord
  alias Storyarn.Scenes.References.Projections.SheetAvatarRecord, as: ReferencesAvatarRecord
  alias Storyarn.Scenes.References.Projections.SheetRecord, as: ReferencesSheetRecord
  alias Storyarn.Scenes.References.Projections.WorkspaceRecord, as: ReferencesWorkspaceRecord
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.Versioning.Entities.AssetRecord, as: VersioningAssetRecord
  alias Storyarn.Scenes.Versioning.EntityVersionRecord
  alias Storyarn.Scenes.Versioning.Projections.BlockRecord, as: VersioningBlockRecord
  alias Storyarn.Scenes.Versioning.Projections.ProjectRecord, as: VersioningProjectRecord
  alias Storyarn.Scenes.Versioning.Projections.SheetAvatarRecord, as: VersioningAvatarRecord
  alias Storyarn.Scenes.Versioning.Projections.SheetRecord, as: VersioningSheetRecord
  alias Storyarn.Scenes.Versioning.Projections.UserRecord, as: VersioningUserRecord
  alias Storyarn.Scenes.Versioning.Projections.WorkspaceRecord, as: VersioningWorkspaceRecord

  test "owned schemas associate to the projection of their own Scene capability" do
    assert association(AccessProjectRecord, :workspace) == AccessWorkspaceRecord
    assert association(AssetsProjectRecord, :workspace) == AssetsWorkspaceRecord

    assert association(Scene, :project) == EditorProjectRecord
    assert association(Scene, :background_asset) == EditorAssetRecord
    assert association(Scene, :current_version) == EditorVersionRecord
    assert association(ScenePin, :sheet) == EditorSheetRecord
    assert association(ScenePin, :flow) == EditorFlowRecord
    assert association(ScenePin, :icon_asset) == EditorAssetRecord
    assert association(SceneZone, :label_icon_asset) == EditorAssetRecord

    assert association(ExplorationSession, :project) == ExplorationProjectRecord
    assert association(ExplorationSession, :user) == ExplorationUserRecord
    assert association(ExplorationSheetRecord, :avatars) == ExplorationAvatarRecord
    assert association(ExplorationAvatarRecord, :asset) == ExplorationAssetRecord

    assert association(HealthBlockRecord, :sheet) == HealthSheetRecord
    assert association(HealthSheetRecord, :avatars) == HealthAvatarRecord
    assert association(HealthAvatarRecord, :asset) == HealthAssetRecord

    assert association(ReferencesProjectRecord, :workspace) == ReferencesWorkspaceRecord
    assert association(ReferencesBlockRecord, :sheet) == ReferencesSheetRecord
    assert association(ReferencesSheetRecord, :avatars) == ReferencesAvatarRecord
    assert association(ReferencesAvatarRecord, :asset) == ReferencesAssetRecord

    assert association(EntityVersionRecord, :project) == VersioningProjectRecord
    assert association(EntityVersionRecord, :created_by) == VersioningUserRecord
    assert association(VersioningProjectRecord, :workspace) == VersioningWorkspaceRecord
    assert association(VersioningBlockRecord, :sheet) == VersioningSheetRecord
    assert association(VersioningSheetRecord, :avatars) == VersioningAvatarRecord
    assert association(VersioningAvatarRecord, :asset) == VersioningAssetRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
