defmodule Storyarn.Scenes.Versioning.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Versioning.EntityVersionRecord
  alias Storyarn.Scenes.Versioning.Projections.ProjectRecord
  alias Storyarn.Scenes.Versioning.Projections.UserRecord
  alias Storyarn.Scenes.Versioning.Projections.WorkspaceRecord

  test "version history associates only to versioning-owned foreign projections" do
    assert association(EntityVersionRecord, :project) == ProjectRecord
    assert association(EntityVersionRecord, :created_by) == UserRecord
    assert association(ProjectRecord, :workspace) == WorkspaceRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
