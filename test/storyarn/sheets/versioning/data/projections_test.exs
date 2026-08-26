defmodule Storyarn.Sheets.Versioning.Data.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Versioning.Data.ProjectRecord
  alias Storyarn.Sheets.Versioning.Data.SheetRecord
  alias Storyarn.Sheets.Versioning.Data.UserRecord
  alias Storyarn.Sheets.Versioning.Data.WorkspaceRecord
  alias Storyarn.Sheets.Versioning.EntityVersionRecord

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
