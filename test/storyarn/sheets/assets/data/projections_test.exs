defmodule Storyarn.Sheets.Assets.Data.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Assets.Data.AssetRecord
  alias Storyarn.Sheets.Assets.Data.ProjectRecord
  alias Storyarn.Sheets.Assets.Data.WorkspaceRecord

  test "asset persistence uses consumer-local projections" do
    assert AssetRecord.__schema__(:source) == "assets"
    assert ProjectRecord.__schema__(:source) == "projects"
    assert association(ProjectRecord, :workspace) == WorkspaceRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
