defmodule Storyarn.Ideation.Groups.View do
  @moduledoc false

  def group(group, members) do
    group
    |> Map.take([:id, :session_id, :author_id, :title, :synthesis, :version, :canvas, :deleted_at, :inserted_at])
    |> Map.put(:idea_ids, Enum.map(members, & &1.idea_id))
    |> Map.put(:members, members)
  end
end
