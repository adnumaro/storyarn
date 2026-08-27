defmodule Storyarn.Sheets.Assets.Projections.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Assets.Entities.AssetRecord
  alias Storyarn.Sheets.Assets.Projections.ProjectRecord
  alias Storyarn.Sheets.Assets.Projections.WorkspaceRecord

  test "asset persistence uses consumer-local projections" do
    assert AssetRecord.__schema__(:source) == "assets"
    assert ProjectRecord.__schema__(:source) == "projects"
    assert association(ProjectRecord, :workspace) == WorkspaceRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
