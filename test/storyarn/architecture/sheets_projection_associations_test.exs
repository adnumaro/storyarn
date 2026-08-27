defmodule Storyarn.Architecture.SheetsProjectionAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Access.Projections.ProjectRecord, as: AccessProjectRecord
  alias Storyarn.Sheets.Access.Projections.WorkspaceRecord, as: AccessWorkspaceRecord
  alias Storyarn.Sheets.Assets.Projections.ProjectRecord, as: AssetsProjectRecord
  alias Storyarn.Sheets.Assets.Projections.WorkspaceRecord, as: AssetsWorkspaceRecord
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Editor.Projections.AssetRecord, as: EditorAssetRecord
  alias Storyarn.Sheets.Editor.Projections.ProjectRecord, as: EditorProjectRecord
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Sheets.Versioning.EntityVersionRecord
  alias Storyarn.Sheets.Versioning.Projections.ProjectRecord, as: VersioningProjectRecord
  alias Storyarn.Sheets.Versioning.Projections.UserRecord, as: VersioningUserRecord
  alias Storyarn.Sheets.Versioning.Projections.WorkspaceRecord, as: VersioningWorkspaceRecord

  test "owned schemas associate to the projection of their own Sheet capability" do
    assert association(AccessProjectRecord, :workspace) == AccessWorkspaceRecord
    assert association(AssetsProjectRecord, :workspace) == AssetsWorkspaceRecord

    assert association(Sheet, :project) == EditorProjectRecord
    assert association(Sheet, :banner_asset) == EditorAssetRecord
    assert association(Sheet, :current_version) == EntityVersionRecord
    assert association(Sheet, :parent) == Sheet
    assert association(Sheet, :children) == Sheet
    assert association(Sheet, :blocks) == Block
    assert association(Sheet, :avatars) == SheetAvatar

    assert association(Block, :sheet) == Sheet
    assert association(Block, :inherited_from_block) == Block
    assert association(Block, :inherited_instances) == Block
    assert association(Block, :table_columns) == TableColumn
    assert association(Block, :table_rows) == TableRow
    assert association(Block, :gallery_images) == BlockGalleryImage

    assert association(BlockGalleryImage, :block) == Block
    assert association(BlockGalleryImage, :asset) == EditorAssetRecord
    assert association(SheetAvatar, :sheet) == Sheet
    assert association(SheetAvatar, :asset) == EditorAssetRecord
    assert association(TableColumn, :block) == Block
    assert association(TableRow, :block) == Block

    assert association(EntityVersionRecord, :project) == VersioningProjectRecord
    assert association(EntityVersionRecord, :created_by) == VersioningUserRecord
    assert association(VersioningProjectRecord, :workspace) == VersioningWorkspaceRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
