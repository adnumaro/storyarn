defmodule Storyarn.Scenes.Exploration.Data.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Exploration.Data.AssetRecord
  alias Storyarn.Scenes.Exploration.Data.FlowConnectionRecord
  alias Storyarn.Scenes.Exploration.Data.FlowNodeRecord
  alias Storyarn.Scenes.Exploration.Data.FlowRecord
  alias Storyarn.Scenes.Exploration.Data.ProjectRecord
  alias Storyarn.Scenes.Exploration.Data.SheetAvatarRecord
  alias Storyarn.Scenes.Exploration.Data.SheetRecord
  alias Storyarn.Scenes.Exploration.Data.UserRecord
  alias Storyarn.Scenes.ExplorationSession

  test "exploration owns the projections needed by sessions and runtime queries" do
    assert FlowRecord.__schema__(:source) == "flows"
    assert FlowNodeRecord.__schema__(:source) == "flow_nodes"
    assert FlowConnectionRecord.__schema__(:source) == "flow_connections"
    assert SheetRecord.__schema__(:source) == "sheets"
    assert SheetAvatarRecord.__schema__(:source) == "sheet_avatars"
    assert AssetRecord.__schema__(:source) == "assets"
    assert ProjectRecord.__schema__(:source) == "projects"
    assert UserRecord.__schema__(:source) == "users"
  end

  test "session and speaker associations use exploration-owned foreign projections" do
    assert ExplorationSession.__schema__(:association, :user).related == UserRecord
    assert ExplorationSession.__schema__(:association, :project).related == ProjectRecord
    assert SheetRecord.__schema__(:association, :avatars).related == SheetAvatarRecord
    assert SheetAvatarRecord.__schema__(:association, :asset).related == AssetRecord
  end
end
