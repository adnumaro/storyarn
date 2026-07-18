defmodule Storyarn.Scenes.SceneReferenceIntegrity do
  @moduledoc """
  Transactional ownership checks for productive scene writers.

  A database foreign key only proves that a referenced row exists. Scene
  references also have to remain inside the source project, point at active
  hierarchical entities, and preserve scene-local relationships such as
  connection endpoints and tree parents.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Project
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.ScenePin

  @type project_lock :: :share | :update

  @doc """
  Runs a mutation with its active owning project and scene locked.

  The lightweight owner lookup is followed by locks on the actual persisted
  rows, so callers never trust the project or scene ownership carried by a
  stale struct.
  """
  @spec with_active_scene_lock(
          term(),
          (Scene.t() -> {:ok, term()} | {:error, term()})
        ) :: {:ok, term()} | {:error, term()}
  def with_active_scene_lock(scene_id, fun) when is_function(fun, 1) do
    with_active_scene_lock(scene_id, [], fun)
  end

  @spec with_active_scene_lock(
          term(),
          keyword(),
          (Scene.t() -> {:ok, term()} | {:error, term()})
        ) :: {:ok, term()} | {:error, term()}
  def with_active_scene_lock(scene_id, opts, fun) when is_list(opts) and is_function(fun, 1) do
    # Scene child tables have activity triggers that update the owning project.
    # Taking an update lock up front avoids two child writers deadlocking while
    # both try to upgrade a shared project lock from their trigger.
    project_lock = Keyword.get(opts, :project_lock, :update)

    Repo.transaction(fn ->
      with {:ok, normalized_scene_id} <- normalize_required_id(scene_id, :scene_id),
           {:ok, project_id} <- fetch_scene_project_id(normalized_scene_id),
           {:ok, _project} <- lock_active_project(project_id, project_lock),
           {:ok, scene} <- lock_active_scene(normalized_scene_id, project_id),
           {:ok, value} <- fun.(scene) do
        value
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Locks an active project. Productive scene writers use an update lock as their
  common serialization point because their activity triggers update this row.
  """
  @spec lock_active_project(term(), project_lock()) ::
          {:ok, Project.t()} | {:error, :project_not_found | :project_not_active | {:invalid_project_id, term()}}
  def lock_active_project(project_id, lock_mode \\ :share) do
    with {:ok, normalized_project_id} <- normalize_required_id(project_id, :project_id) do
      query = apply_lock(from(project in Project, where: project.id == ^normalized_project_id), lock_mode)

      case Repo.one(query) do
        %Project{deleted_at: nil} = project -> {:ok, project}
        %Project{} -> {:error, :project_not_active}
        nil -> {:error, :project_not_found}
      end
    end
  end

  @doc """
  Validates and normalizes a scene's parent and background asset.

  The effective values are checked, not just changed values, so unrelated
  updates cannot preserve a pre-existing cross-project reference silently.
  """
  @spec lock_scene_root_references(Scene.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def lock_scene_root_references(%Scene{} = scene, attrs) when is_map(attrs) do
    parent_value = effective_value(attrs, "parent_id", scene.parent_id)
    background_value = effective_value(attrs, "background_asset_id", scene.background_asset_id)
    scene_context = scene.id || :new

    specs = [
      {:scene, {:scene, scene_context, :parent_id}, parent_value},
      {:asset, {:scene, scene_context, :background_asset_id}, background_value}
    ]

    with {:ok, [parent_id, background_asset_id]} <-
           ProjectReferenceIntegrity.lock_active_references(scene.project_id, specs),
         :ok <-
           ProjectReferenceIntegrity.ensure_locked_asset_content_type(
             scene.project_id,
             background_asset_id,
             {:scene, scene_context, :background_asset_id},
             "image/%"
           ),
         :ok <- validate_parent_chain(scene, parent_id) do
      {:ok,
       attrs
       |> Map.put("parent_id", parent_id)
       |> Map.put("background_asset_id", background_asset_id)}
    end
  end

  @doc """
  Validates and locks a prospective parent for an existing scene.
  """
  @spec lock_scene_parent(Scene.t(), term()) :: {:ok, integer() | nil} | {:error, term()}
  def lock_scene_parent(%Scene{} = scene, parent_value) do
    context = {:scene, scene.id, :parent_id}

    with {:ok, [parent_id]} <-
           ProjectReferenceIntegrity.lock_active_references(
             scene.project_id,
             [{:scene, context, parent_value}]
           ),
         :ok <- validate_parent_chain(scene, parent_id) do
      {:ok, parent_id}
    end
  end

  @doc """
  Validates a pin's effective sheet, flow and icon asset references.
  """
  @spec lock_pin_references(Scene.t(), ScenePin.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def lock_pin_references(%Scene{} = scene, %ScenePin{} = pin, attrs) when is_map(attrs) do
    source_id = pin.id || :new

    specs = [
      {:sheet, {:scene_pin, source_id, :sheet_id}, effective_value(attrs, "sheet_id", pin.sheet_id)},
      {:flow, {:scene_pin, source_id, :flow_id}, effective_value(attrs, "flow_id", pin.flow_id)},
      {:asset, {:scene_pin, source_id, :icon_asset_id}, effective_value(attrs, "icon_asset_id", pin.icon_asset_id)}
    ]

    with {:ok, [sheet_id, flow_id, icon_asset_id]} <-
           ProjectReferenceIntegrity.lock_active_references(scene.project_id, specs),
         :ok <-
           ProjectReferenceIntegrity.ensure_locked_asset_content_type(
             scene.project_id,
             icon_asset_id,
             {:scene_pin, source_id, :icon_asset_id},
             "image/%"
           ) do
      {:ok,
       attrs
       |> Map.put("sheet_id", sheet_id)
       |> Map.put("flow_id", flow_id)
       |> Map.put("icon_asset_id", icon_asset_id)}
    end
  end

  @doc """
  Validates a zone's effective typed target and label icon asset.

  Pair and action-type semantics remain changeset responsibilities. This
  function adds ownership, active-state and ID-shape guarantees for recognized
  productive target types.
  """
  @spec lock_zone_references(Scene.t(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def lock_zone_references(%Scene{} = scene, zone, attrs) when is_map(zone) and is_map(attrs) do
    source_id = Map.get(zone, :id) || :new
    icon_value = effective_value(attrs, "label_icon_asset_id", Map.get(zone, :label_icon_asset_id))
    target_type = effective_value(attrs, "target_type", Map.get(zone, :target_type))
    target_value = effective_value(attrs, "target_id", Map.get(zone, :target_id))
    action_type = effective_value(attrs, "action_type", Map.get(zone, :action_type))
    action_data = effective_value(attrs, "action_data", Map.get(zone, :action_data))

    with {:ok, [label_icon_asset_id]} <-
           ProjectReferenceIntegrity.lock_active_references(
             scene.project_id,
             [
               {:asset, {:scene_zone, source_id, :label_icon_asset_id}, icon_value}
             ]
           ),
         :ok <-
           ProjectReferenceIntegrity.ensure_locked_asset_content_type(
             scene.project_id,
             label_icon_asset_id,
             {:scene_zone, source_id, :label_icon_asset_id},
             "image/%"
           ),
         {:ok, target_id} <-
           lock_zone_target(scene.project_id, source_id, target_type, target_value),
         {:ok, action_data} <-
           lock_zone_action_data_references(
             scene.project_id,
             source_id,
             action_type,
             action_data
           ) do
      attrs =
        attrs
        |> Map.put("label_icon_asset_id", label_icon_asset_id)
        |> Map.put("action_data", action_data)
        |> maybe_put_normalized_target(target_type, target_id)

      {:ok, attrs}
    end
  end

  @doc """
  Validates and locks connection endpoints for creation.
  """
  @spec lock_connection_endpoints(Scene.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def lock_connection_endpoints(%Scene{} = scene, attrs) when is_map(attrs) do
    validate_connection_endpoint_values(
      scene,
      attrs,
      Map.get(attrs, "from_pin_id"),
      Map.get(attrs, "to_pin_id")
    )
  end

  @doc """
  Revalidates and locks the persisted endpoints of an existing connection.
  """
  @spec lock_connection_endpoints(Scene.t(), SceneConnection.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def lock_connection_endpoints(%Scene{} = scene, %SceneConnection{} = connection, attrs) when is_map(attrs) do
    validate_connection_endpoint_values(
      scene,
      attrs,
      connection.from_pin_id,
      connection.to_pin_id
    )
  end

  defp fetch_scene_project_id(scene_id) do
    case Repo.one(from(scene in Scene, where: scene.id == ^scene_id, select: scene.project_id)) do
      project_id when is_integer(project_id) -> {:ok, project_id}
      nil -> {:error, :scene_not_found}
    end
  end

  defp lock_active_scene(scene_id, project_id) do
    query =
      from(scene in Scene,
        where: scene.id == ^scene_id and scene.project_id == ^project_id,
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      %Scene{deleted_at: nil} = scene -> {:ok, scene}
      %Scene{} -> {:error, :scene_not_active}
      nil -> {:error, :scene_not_found}
    end
  end

  defp validate_parent_chain(%Scene{}, nil), do: :ok

  defp validate_parent_chain(%Scene{id: scene_id}, scene_id) do
    {:error, {:invalid_scene_parent, scene_id, scene_id, :self}}
  end

  defp validate_parent_chain(%Scene{} = scene, parent_id) do
    walk_parent_chain(scene, parent_id, MapSet.new(), 0)
  end

  defp walk_parent_chain(scene, current_id, _seen, depth) when depth > 1_000 do
    {:error, {:invalid_scene_parent, scene.id, current_id, :depth_limit}}
  end

  defp walk_parent_chain(scene, current_id, seen, depth) do
    cond do
      current_id == scene.id ->
        {:error, {:invalid_scene_parent, scene.id, current_id, :cycle}}

      MapSet.member?(seen, current_id) ->
        {:error, {:invalid_scene_parent, scene.id, current_id, :existing_cycle}}

      true ->
        case lock_parent_row(scene.project_id, current_id) do
          {:ok, nil} ->
            :ok

          {:ok, parent_id} ->
            walk_parent_chain(
              scene,
              parent_id,
              MapSet.put(seen, current_id),
              depth + 1
            )

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp lock_parent_row(project_id, scene_id) do
    case Repo.one(
           from(scene in Scene,
             where:
               scene.id == ^scene_id and scene.project_id == ^project_id and
                 is_nil(scene.deleted_at),
             lock: "FOR SHARE",
             select: {scene.id, scene.parent_id}
           )
         ) do
      nil ->
        context = {:scene_parent_chain, scene_id}
        {:error, {:invalid_project_reference, context, scene_id}}

      {^scene_id, parent_id} ->
        {:ok, parent_id}
    end
  end

  defp lock_zone_target(_project_id, _source_id, target_type, target_id) when target_type not in ["flow", "scene"] do
    {:ok, target_id}
  end

  defp lock_zone_target(project_id, source_id, target_type, target_value) do
    type = if target_type == "flow", do: :flow, else: :scene
    context = {:scene_zone, source_id, :target_id}

    with {:ok, [target_id]} <-
           ProjectReferenceIntegrity.lock_active_references(
             project_id,
             [{type, context, target_value}]
           ) do
      {:ok, target_id}
    end
  end

  defp maybe_put_normalized_target(attrs, target_type, target_id) when target_type in ["flow", "scene"] do
    Map.put(attrs, "target_id", target_id)
  end

  defp maybe_put_normalized_target(attrs, _target_type, _target_id), do: attrs

  defp lock_zone_action_data_references(project_id, source_id, "collection", action_data) when is_map(action_data) do
    items = Map.get(action_data, "items", Map.get(action_data, :items))
    lock_collection_action_data_references(project_id, source_id, action_data, items)
  end

  defp lock_zone_action_data_references(_project_id, _source_id, _action_type, action_data), do: {:ok, action_data}

  defp lock_collection_action_data_references(project_id, source_id, action_data, items) when is_list(items) do
    with {:ok, item_specs} <- collection_item_specs(items, source_id),
         {:ok, normalized_sheet_ids} <-
           ProjectReferenceIntegrity.lock_active_references(
             project_id,
             Enum.map(item_specs, &elem(&1, 1))
           ) do
      normalized_items = normalize_collection_items(item_specs, normalized_sheet_ids)

      {:ok,
       action_data
       |> Map.delete(:items)
       |> Map.put("items", normalized_items)}
    end
  end

  defp lock_collection_action_data_references(_project_id, _source_id, action_data, _items) do
    # The changeset owns the user-facing shape error for a missing/non-list
    # items field.
    {:ok, action_data}
  end

  defp normalize_collection_items(item_specs, normalized_sheet_ids) do
    item_specs
    |> Enum.zip(normalized_sheet_ids)
    |> Enum.map(fn {{item, _spec}, sheet_id} ->
      item
      |> Map.delete(:sheet_id)
      |> Map.put("sheet_id", sheet_id)
    end)
  end

  defp collection_item_specs(items, source_id) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, [], MapSet.new()},
      &reduce_collection_item_spec(&1, &2, source_id)
    )
    |> case do
      {:ok, specs, _seen_ids} -> {:ok, Enum.reverse(specs)}
      {:error, _reason} = error -> error
    end
  end

  defp reduce_collection_item_spec({item, index}, {:ok, specs, seen_ids}, source_id) when is_map(item) do
    case normalize_collection_item_id(item, source_id, index) do
      {:ok, item_id} ->
        reduce_normalized_collection_item(item, item_id, index, specs, seen_ids, source_id)

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp reduce_collection_item_spec({item, index}, _acc, source_id) do
    context = {:scene_zone, source_id, :collection_item, index}
    {:halt, {:error, {:invalid_project_reference, context, item}}}
  end

  defp reduce_normalized_collection_item(item, item_id, index, specs, seen_ids, source_id) do
    if MapSet.member?(seen_ids, item_id) do
      {:halt, {:error, {:invalid_scene_collection_item, source_id, index, :duplicate_id, item_id}}}
    else
      raw_sheet_id = Map.get(item, "sheet_id", Map.get(item, :sheet_id))
      context = {:scene_zone, source_id, :collection_item, index, :sheet_id}
      spec = {:sheet, context, raw_sheet_id}

      normalized_item =
        item
        |> Map.delete(:id)
        |> Map.put("id", item_id)

      {:cont, {:ok, [{normalized_item, spec} | specs], MapSet.put(seen_ids, item_id)}}
    end
  end

  defp normalize_collection_item_id(item, source_id, index) do
    value = Map.get(item, "id", Map.get(item, :id))

    case Ecto.UUID.cast(value) do
      {:ok, normalized_id} ->
        {:ok, normalized_id}

      :error ->
        {:error, {:invalid_scene_collection_item, source_id, index, :invalid_id, value}}
    end
  end

  defp validate_connection_endpoint_values(%Scene{} = scene, attrs, from_pin_value, to_pin_value) do
    with {:ok, from_pin_id} <-
           normalize_endpoint_id(:from_pin_id, from_pin_value),
         {:ok, to_pin_id} <-
           normalize_endpoint_id(:to_pin_id, to_pin_value),
         :ok <-
           lock_pins_for_scene(
             scene.id,
             [
               {:from_pin_id, from_pin_id, from_pin_value},
               {:to_pin_id, to_pin_id, to_pin_value}
             ]
           ) do
      {:ok,
       attrs
       |> Map.put("from_pin_id", from_pin_id)
       |> Map.put("to_pin_id", to_pin_id)}
    end
  end

  defp normalize_endpoint_id(context, value) do
    case ProjectReferenceIntegrity.normalize_optional_id(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_scene_connection_endpoint, context, value}}
    end
  end

  defp lock_pins_for_scene(scene_id, endpoint_specs) do
    pin_ids =
      endpoint_specs
      |> Enum.map(&elem(&1, 1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    owned_pin_ids =
      if pin_ids == [] do
        MapSet.new()
      else
        ScenePin
        |> where([pin], pin.id in ^pin_ids and pin.scene_id == ^scene_id)
        |> order_by([pin], asc: pin.id)
        |> lock("FOR SHARE")
        |> select([pin], pin.id)
        |> Repo.all()
        |> MapSet.new()
      end

    case Enum.find(endpoint_specs, fn {_context, pin_id, _value} ->
           not is_nil(pin_id) and not MapSet.member?(owned_pin_ids, pin_id)
         end) do
      nil ->
        :ok

      {context, _pin_id, value} ->
        {:error, {:invalid_scene_connection_endpoint, context, value}}
    end
  end

  defp effective_value(attrs, field, current) do
    atom_field = String.to_existing_atom(field)

    cond do
      Map.has_key?(attrs, field) -> Map.get(attrs, field)
      Map.has_key?(attrs, atom_field) -> Map.get(attrs, atom_field)
      true -> current
    end
  end

  defp normalize_required_id(value, context) do
    case ProjectReferenceIntegrity.normalize_optional_id(value) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _other -> {:error, {invalid_id_error(context), value}}
    end
  end

  defp invalid_id_error(:project_id), do: :invalid_project_id
  defp invalid_id_error(:scene_id), do: :invalid_scene_id

  defp apply_lock(query, :share), do: lock(query, "FOR SHARE")
  defp apply_lock(query, :update), do: lock(query, "FOR UPDATE")
end
