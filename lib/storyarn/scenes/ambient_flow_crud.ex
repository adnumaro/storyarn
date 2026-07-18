defmodule Storyarn.Scenes.AmbientFlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Shared.MapUtils

  @doc """
  Lists ambient flows for a scene, ordered by position then id.
  Preloads the flow association.
  """
  def list_ambient_flows(scene_id) do
    Repo.all(
      from(af in SceneAmbientFlow,
        where: af.scene_id == ^scene_id,
        order_by: [asc: af.position, desc: af.priority, asc: af.id],
        preload: [:flow]
      )
    )
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

    with_active_scene_lock(scene_id, fn scene ->
      with {:ok, flow_id} <- requested_flow_id(attrs, nil),
           :ok <- lock_active_flow_for_project(flow_id, scene.project_id) do
        next_pos = next_position(scene_id)

        %SceneAmbientFlow{scene_id: scene_id, position: next_pos}
        |> SceneAmbientFlow.changeset(attrs)
        |> Repo.insert()
      end
    end)
  end

  @doc """
  Updates an ambient flow (enabled, trigger_type, trigger_config, priority, position).
  """
  def update_ambient_flow(%SceneAmbientFlow{} = ambient_flow, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    with_active_scene_lock(ambient_flow.scene_id, fn scene ->
      with {:ok, locked_ambient_flow} <-
             lock_ambient_flow_for_scene(ambient_flow.id, ambient_flow.scene_id),
           {:ok, flow_id} <-
             requested_flow_id(attrs, locked_ambient_flow.flow_id),
           :ok <- lock_active_flow_for_project(flow_id, scene.project_id) do
        locked_ambient_flow
        |> SceneAmbientFlow.changeset(attrs)
        |> Repo.update()
      end
    end)
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
        Repo.update_all(from(af in SceneAmbientFlow, where: af.id == ^id and af.scene_id == ^scene_id),
          set: [position: index]
        )
      end)

      list_ambient_flows(scene_id)
    end)
  end

  defp next_position(scene_id) do
    Repo.one(from(af in SceneAmbientFlow, where: af.scene_id == ^scene_id, select: coalesce(max(af.position), -1) + 1))
  end

  defp with_active_scene_lock(scene_id, fun) when is_function(fun, 1) do
    Repo.transaction(fn ->
      Scene
      |> where([scene], scene.id == ^scene_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> run_active_scene_callback(fun)
    end)
  end

  defp run_active_scene_callback(nil, _fun), do: Repo.rollback(:scene_not_found)

  defp run_active_scene_callback(%Scene{deleted_at: nil} = scene, fun) do
    case fun.(scene) do
      {:ok, value} -> value
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp run_active_scene_callback(%Scene{}, _fun), do: Repo.rollback(:scene_not_active)

  defp lock_ambient_flow_for_scene(ambient_flow_id, scene_id) do
    case Repo.one(
           from(ambient_flow in SceneAmbientFlow,
             where:
               ambient_flow.id == ^ambient_flow_id and
                 ambient_flow.scene_id == ^scene_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SceneAmbientFlow{} = ambient_flow -> {:ok, ambient_flow}
      nil -> {:error, :ambient_flow_not_found}
    end
  end

  defp requested_flow_id(attrs, current_flow_id) do
    flow_id =
      if Map.has_key?(attrs, "flow_id") do
        MapUtils.parse_int(attrs["flow_id"])
      else
        current_flow_id
      end

    if is_integer(flow_id) and flow_id > 0 do
      {:ok, flow_id}
    else
      {:error, :invalid_flow_id}
    end
  end

  defp lock_active_flow_for_project(flow_id, project_id) do
    case Repo.one(
           from(flow in Flow,
             where: flow.id == ^flow_id,
             lock: "FOR UPDATE"
           )
         ) do
      nil ->
        {:error, :flow_not_found}

      %Flow{deleted_at: nil, project_id: ^project_id} ->
        :ok

      %Flow{deleted_at: nil} ->
        {:error, :cross_project}

      %Flow{} ->
        {:error, :flow_not_active}
    end
  end
end
