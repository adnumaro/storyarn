defmodule Storyarn.Flows.SceneResolver do
  @moduledoc """
  Resolves which map should be the backdrop for a flow.

  Resolution order:
  1. `flow.scene_map_id` (explicit, authoritative)
  2. `opts[:caller_scene_map_id]` (runtime inheritance from calling flow)
  3. Walk up `parent_id` chain looking for `scene_map_id` (first found wins)
  4. `nil` (no backdrop)
  """

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo

  @doc """
  Resolves the scene_map_id for a flow.

  ## Options
    - `:caller_scene_map_id` - scene_map_id from the calling flow (runtime inheritance)
  """
  @spec resolve_scene_map_id(Flow.t(), keyword()) :: integer() | nil
  def resolve_scene_map_id(%Flow{} = flow, opts \\ []) do
    cond do
      flow.scene_map_id -> flow.scene_map_id
      opts[:caller_scene_map_id] -> opts[:caller_scene_map_id]
      flow.parent_id -> resolve_from_ancestors(flow.parent_id)
      true -> nil
    end
  end

  # Walk up the parent chain looking for a scene_map_id.
  # Flow trees are shallow (typically <5 levels), so recursive
  # single-row queries are acceptable for mount-time resolution.
  @max_depth 10

  defp resolve_from_ancestors(parent_id, depth \\ 0)
  defp resolve_from_ancestors(_parent_id, depth) when depth >= @max_depth, do: nil
  defp resolve_from_ancestors(nil, _depth), do: nil

  defp resolve_from_ancestors(parent_id, depth) do
    case Repo.one(
           from(f in Flow,
             where: f.id == ^parent_id and is_nil(f.deleted_at),
             select: %{parent_id: f.parent_id, scene_map_id: f.scene_map_id}
           )
         ) do
      %{scene_map_id: sid} when not is_nil(sid) -> sid
      %{parent_id: pid} -> resolve_from_ancestors(pid, depth + 1)
      nil -> nil
    end
  end
end
