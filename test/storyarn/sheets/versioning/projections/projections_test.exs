defmodule Storyarn.Sheets.Versioning.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Versioning.EntityVersionRecord
  alias Storyarn.Sheets.Versioning.Projections.ProjectRecord
  alias Storyarn.Sheets.Versioning.Projections.SheetRecord
  alias Storyarn.Sheets.Versioning.Projections.UserRecord
  alias Storyarn.Sheets.Versioning.Projections.WorkspaceRecord

  test "version history associates only to versioning-owned foreign projections" do
    assert association(EntityVersionRecord, :project) == ProjectRecord
    assert association(EntityVersionRecord, :created_by) == UserRecord
    assert association(ProjectRecord, :workspace) == WorkspaceRecord
  end

  test "the cross-capability Sheet projection stays deliberately narrow" do
    assert SheetRecord.__schema__(:source) == "sheets"
    assert SheetRecord.__schema__(:fields) == [:id, :project_id, :deleted_at]
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
