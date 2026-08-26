defmodule Storyarn.Scenes.Versioning.Data.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Versioning.Data.ProjectRecord
  alias Storyarn.Scenes.Versioning.Data.UserRecord
  alias Storyarn.Scenes.Versioning.Data.WorkspaceRecord
  alias Storyarn.Scenes.Versioning.EntityVersionRecord

  test "version history associates only to versioning-owned foreign projections" do
    assert association(EntityVersionRecord, :project) == ProjectRecord
    assert association(EntityVersionRecord, :created_by) == UserRecord
    assert association(ProjectRecord, :workspace) == WorkspaceRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end
