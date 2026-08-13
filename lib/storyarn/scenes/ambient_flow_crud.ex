defmodule Storyarn.Scenes.AmbientFlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows.Flow
  alias Storyarn.References
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneReferenceIntegrity
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

    scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, flow_id} <- requested_flow_id(attrs, nil),
           :ok <- lock_active_flow_for_project(flow_id, scene.project_id),
           next_pos = next_position(scene.id),
           {:ok, ambient_flow} <-
             %SceneAmbientFlow{scene_id: scene.id, position: next_pos}
             |> SceneAmbientFlow.changeset(Map.put(attrs, "flow_id", flow_id))
             |> Repo.insert(),
           :ok <-
             References.update_scene_ambient_flow_variable_references(
               ambient_flow,
               project_id: scene.project_id
             ) do
        {:ok, {ambient_flow, scene.project_id, true}}
      end
    end)
    |> broadcast_ambient_flow_result()
  end

  @doc """
  Updates an ambient flow (enabled, trigger_type, trigger_config, priority, position).
  """
  def update_ambient_flow(%SceneAmbientFlow{} = ambient_flow, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    ambient_flow.scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_ambient_flow} <-
             lock_ambient_flow_for_scene(ambient_flow.id, scene.id),
           {:ok, flow_id} <-
             requested_flow_id(attrs, locked_ambient_flow.flow_id),
           :ok <- lock_active_flow_for_project(flow_id, scene.project_id),
           {:ok, updated_ambient_flow, changed?} <-
             locked_ambient_flow
             |> SceneAmbientFlow.changeset(Map.put(attrs, "flow_id", flow_id))
             |> update_ambient_flow_if_changed(locked_ambient_flow),
           :ok <-
             References.update_scene_ambient_flow_variable_references(
               updated_ambient_flow,
               project_id: scene.project_id
             ) do
        {:ok, {updated_ambient_flow, scene.project_id, changed?}}
      end
    end)
    |> broadcast_ambient_flow_result()
  end

  @doc """
  Deletes an ambient flow link.
  """
  def delete_ambient_flow(%SceneAmbientFlow{} = ambient_flow) do
    ambient_flow.scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_ambient_flow} <-
             lock_ambient_flow_for_scene(ambient_flow.id, scene.id),
           {:ok, deleted_ambient_flow} <- Repo.delete(locked_ambient_flow),
           :ok <-
             References.delete_scene_ambient_flow_variable_references(locked_ambient_flow.id) do
        {:ok, {deleted_ambient_flow, scene.project_id, true}}
      end
    end)
    |> broadcast_ambient_flow_result()
  end

  @doc """
  Reorders ambient flows by updating positions from the given ordered IDs list.
  """
  def reorder_ambient_flows(scene_id, ordered_ids) when is_list(ordered_ids) do
    scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, normalized_ids} <- normalize_reorder_ids(ordered_ids),
           {:ok, current_ids} <-
             lock_complete_ambient_flow_set(scene.id, normalized_ids) do
        changed? = current_ids != normalized_ids
        maybe_persist_ambient_flow_positions(changed?, scene.id, normalized_ids)

        {:ok, {list_ambient_flows(scene.id), scene.project_id, changed?}}
      end
    end)
    |> broadcast_ambient_flow_result()
  end

  defp maybe_persist_ambient_flow_positions(true, scene_id, normalized_ids),
    do: persist_ambient_flow_positions(scene_id, normalized_ids)

  defp maybe_persist_ambient_flow_positions(false, _scene_id, _normalized_ids), do: :ok

  defp persist_ambient_flow_positions(scene_id, normalized_ids) do
    normalized_ids
    |> Enum.with_index()
    |> Enum.each(fn {id, index} ->
      Repo.update_all(
        from(ambient_flow in SceneAmbientFlow,
          where:
            ambient_flow.id == ^id and
              ambient_flow.scene_id == ^scene_id
        ),
        set: [position: index]
      )
    end)
  end

  defp next_position(scene_id) do
    Repo.one(from(af in SceneAmbientFlow, where: af.scene_id == ^scene_id, select: coalesce(max(af.position), -1) + 1))
  end

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

  defp lock_complete_ambient_flow_set(scene_id, ambient_flow_ids) do
    locked_ambient_flows =
      Repo.all(
        from(ambient_flow in SceneAmbientFlow,
          where: ambient_flow.scene_id == ^scene_id,
          order_by: [asc: ambient_flow.id],
          lock: "FOR UPDATE",
          select: %{
            id: ambient_flow.id,
            position: ambient_flow.position,
            priority: ambient_flow.priority
          }
        )
      )

    locked_ids = Enum.map(locked_ambient_flows, & &1.id)

    if locked_ids == Enum.sort(ambient_flow_ids) do
      current_ids =
        locked_ambient_flows
        |> Enum.sort_by(&{&1.position, -&1.priority, &1.id})
        |> Enum.map(& &1.id)

      {:ok, current_ids}
    else
      {:error, {:invalid_scene_ambient_flow_reorder, ambient_flow_ids}}
    end
  end

  defp update_ambient_flow_if_changed(%Ecto.Changeset{valid?: true, changes: changes}, locked_ambient_flow)
       when map_size(changes) == 0, do: {:ok, locked_ambient_flow, false}

  defp update_ambient_flow_if_changed(changeset, _locked_ambient_flow) do
    case Repo.update(changeset) do
      {:ok, updated_ambient_flow} -> {:ok, updated_ambient_flow, true}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_ambient_flow_result({:ok, {value, project_id, true}}) do
    Collaboration.broadcast_dashboard_change(project_id, :scenes)
    {:ok, value}
  end

  defp broadcast_ambient_flow_result({:ok, {value, _project_id, false}}), do: {:ok, value}

  defp broadcast_ambient_flow_result(result), do: result

  defp normalize_reorder_ids(ambient_flow_ids) do
    with {:ok, normalized_ids} <- normalize_positive_ids(ambient_flow_ids),
         true <- length(normalized_ids) == MapSet.size(MapSet.new(normalized_ids)) do
      {:ok, normalized_ids}
    else
      _error ->
        {:error, {:invalid_scene_ambient_flow_reorder, ambient_flow_ids}}
    end
  end

  defp normalize_positive_ids(ids) do
    ids
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, normalized} ->
      case ProjectReferenceIntegrity.normalize_optional_id(id) do
        {:ok, normalized_id} when is_integer(normalized_id) ->
          {:cont, {:ok, [normalized_id | normalized]}}

        _error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end
end
