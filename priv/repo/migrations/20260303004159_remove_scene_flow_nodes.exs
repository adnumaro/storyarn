defmodule Storyarn.Repo.Migrations.RemoveSceneFlowNodes do
  use Ecto.Migration

  def up do
    execute "UPDATE flow_nodes SET type = 'slug_line' WHERE type = 'scene'"
  end

  def down do
    execute "UPDATE flow_nodes SET type = 'scene' WHERE type = 'slug_line'"
  end
end
