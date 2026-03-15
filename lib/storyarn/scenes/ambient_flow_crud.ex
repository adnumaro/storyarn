defmodule Storyarn.Scenes.AmbientFlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Shared.MapUtils

  @doc """
  Lists ambient flows for a scene, ordered by position then id.
  Preloads the flow association.
  """
  def list_ambient_flows(scene_id) do
    from(af in SceneAmbientFlow,
      where: af.scene_id == ^scene_id,
      order_by: [asc: af.position, asc: af.id],
      preload: [:flow]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single ambient flow scoped to a scene. Returns `nil` if not found.
  """
  def get_ambient_flow(scene_id, id) do
    Repo.get_by(SceneAmbientFlow, id: id, scene_id: scene_id)
  end

  @doc """
  Creates an ambient flow link for a scene.
  Validates the flow belongs to the same project as the scene.
  """
  def create_ambient_flow(scene_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)
    flow_id = MapUtils.parse_int(attrs["flow_id"])

    with {:ok, _} <- validate_same_project(scene_id, flow_id) do
      next_pos = next_position(scene_id)

      %SceneAmbientFlow{scene_id: scene_id, position: next_pos}
      |> SceneAmbientFlow.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates an ambient flow (enabled, trigger_type, position).
  """
  def update_ambient_flow(%SceneAmbientFlow{} = ambient_flow, attrs) do
    ambient_flow
    |> SceneAmbientFlow.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an ambient flow link.
  """
  def delete_ambient_flow(%SceneAmbientFlow{} = ambient_flow) do
    Repo.delete(ambient_flow)
  end

  @doc """
  Reorders ambient flows by updating positions from the given ordered IDs list.
  """
  def reorder_ambient_flows(scene_id, ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        from(af in SceneAmbientFlow,
          where: af.id == ^id and af.scene_id == ^scene_id
        )
        |> Repo.update_all(set: [position: index])
      end)

      list_ambient_flows(scene_id)
    end)
  end

  defp next_position(scene_id) do
    from(af in SceneAmbientFlow,
      where: af.scene_id == ^scene_id,
      select: coalesce(max(af.position), -1) + 1
    )
    |> Repo.one()
  end

  defp validate_same_project(scene_id, flow_id) when is_integer(flow_id) do
    case Scenes.get_scene_project_id(scene_id) do
      nil ->
        {:error, :scene_not_found}

      scene_project_id ->
        case Repo.get(Flow, flow_id) do
          nil -> {:error, :flow_not_found}
          %{project_id: ^scene_project_id} -> {:ok, :valid}
          _ -> {:error, :cross_project}
        end
    end
  end

  defp validate_same_project(_scene_id, _flow_id), do: {:error, :invalid_flow_id}
end
