defmodule StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers do
  @moduledoc """
  Handles generic node events for the flow editor LiveView.

  Responsible for type-agnostic operations: add, select, deselect, move,
  delete, duplicate, update data/text/field, open/close editor.

  Type-specific event handlers live in their respective `Nodes.{Type}.Node` modules.
  Delegates heavy lifting to NodeHelpers. Returns `{:noreply, socket}`.
  """

  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_patch: 2, put_flash: 3]
  import StoryarnWeb.Helpers.AutoSnapshot, only: [schedule: 2]
  import StoryarnWeb.Helpers.SaveStatusTimer, only: [mark_saved: 1]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers
  alias StoryarnWeb.FlowLive.Helpers.SequencePresentation
  alias StoryarnWeb.FlowLive.NodeTypeRegistry
  alias StoryarnWeb.FlowLive.PickerSearch
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  # Notify the sticky FlowSidebarLive that the flows tree may have changed
  # (flow rename / shortcut change). Show itself no longer owns :flows_tree.
  defp broadcast_flows_tree_changed(socket) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      ProjectChromeHelpers.shell_topic(socket.assigns.project.id),
      {:tree_changed, :flows}
    )

    socket
  end

  @spec handle_add_node(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_add_node(%{"type" => type} = params, socket) do
    opts =
      case {params["position_x"], params["position_y"]} do
        {x, y} when is_number(x) and is_number(y) -> [position: {x, y}]
        _ -> []
      end

    opts =
      case parent_id_param(params["parent_id"]) do
        nil -> opts
        parent_id -> Keyword.put(opts, :parent_id, parent_id)
      end

    NodeHelpers.add_node(socket, type, opts)
  end

  defp parent_id_param(parent_id) when is_integer(parent_id), do: parent_id

  defp parent_id_param(parent_id) when is_binary(parent_id) do
    case Integer.parse(parent_id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parent_id_param(_parent_id), do: nil

  @spec handle_save_name(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_save_name(%{"name" => name}, socket) do
    flow = socket.assigns.flow
    prev_name = flow.name

    case Flows.update_flow(flow, %{name: name}) do
      {:ok, updated_flow} ->
        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> mark_saved()
         |> schedule(:flow)
         |> broadcast_flows_tree_changed()
         |> push_event("flow_meta_changed", %{field: "name", prev: prev_name, new: name})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not save flow name."))}
    end
  end

  @spec handle_save_shortcut(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_save_shortcut(%{"shortcut" => shortcut}, socket) do
    flow = socket.assigns.flow
    prev_shortcut = flow.shortcut
    shortcut = if shortcut == "", do: nil, else: shortcut

    case Flows.update_flow(flow, %{shortcut: shortcut}) do
      {:ok, updated_flow} ->
        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> mark_saved()
         |> schedule(:flow)
         |> broadcast_flows_tree_changed()
         |> push_event("flow_meta_changed", %{
           field: "shortcut",
           prev: prev_shortcut,
           new: shortcut
         })}

      {:error, changeset} ->
        error_msg = format_shortcut_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  @spec handle_restore_flow_meta(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_restore_flow_meta(%{"field" => "name", "value" => value}, socket) do
    flow = socket.assigns.flow

    case Flows.update_flow(flow, %{name: value}) do
      {:ok, updated_flow} ->
        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> mark_saved()
         |> broadcast_flows_tree_changed()
         |> push_event("restore_page_content", %{
           name: updated_flow.name,
           shortcut: updated_flow.shortcut || ""
         })}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not restore flow name."))}
    end
  end

  def handle_restore_flow_meta(%{"field" => "shortcut", "value" => value}, socket) do
    flow = socket.assigns.flow
    shortcut = if value == "" or is_nil(value), do: nil, else: value

    case Flows.update_flow(flow, %{shortcut: shortcut}) do
      {:ok, updated_flow} ->
        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> mark_saved()
         |> broadcast_flows_tree_changed()
         |> push_event("restore_page_content", %{
           name: updated_flow.name,
           shortcut: updated_flow.shortcut || ""
         })}

      {:error, changeset} ->
        error_msg = format_shortcut_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_restore_flow_meta(_params, socket), do: {:noreply, socket}

  @spec handle_node_selected(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_node_selected(%{"id" => node_id}, socket) do
    node = Flows.get_node(socket.assigns.flow.id, node_id)
    if is_nil(node), do: {:noreply, socket}, else: do_handle_node_selected(node_id, node, socket)
  end

  defp do_handle_node_selected(node_id, node, socket) do
    form = FormHelpers.node_data_to_form(node)
    user = socket.assigns.current_scope.user

    socket =
      if socket.assigns.can_edit do
        handle_node_lock_acquisition(socket, node_id, user)
      else
        socket
      end

    send(self(), {:load_node_select_data, node})

    {:noreply,
     socket
     |> assign(:selected_node, node)
     |> assign(:node_form, form)
     |> assign(:editing_mode, :toolbar)
     |> assign(:node_select_loading, true)
     |> assign(:available_flows, [])
     |> assign(:subflow_exits, [])
     |> assign(:referencing_jumps, [])
     |> assign(:referencing_flows, [])
     |> assign(:sequence_panel_data, nil)
     |> assign(:sequence_stage, SequencePresentation.empty_stage())}
  end

  @doc """
  Opens the sequence config sidebar for the currently-selected sequence.
  Mirrors `open_builder` / `open_dialogue_panel`: reads `selected_node`, loads
  the panel payload (config + tracks + asset lists), flips
  `editing_mode` to `:sequence_config`. The panel itself is gated on
  that mode in `show.ex`.
  """
  @spec handle_open_sequence_config(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_open_sequence_config(socket) do
    case socket.assigns.selected_node do
      %{type: type} = node when type in ["sequence", "dialogue"] ->
        {:noreply,
         socket
         |> assign(:editing_mode, :sequence_config)
         |> assign(:sequence_panel_data, build_sequence_panel_data(socket, node))}

      _ ->
        {:noreply, socket}
    end
  end

  @doc "Opens the composition inspector for an explicit stage owner."
  @spec handle_open_sequence_config(map(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_open_sequence_config(%{"id" => node_id}, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         %{type: type} = owner <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         true <- type in ["sequence", "dialogue"],
         {:noreply, selected_socket} <- handle_node_selected(%{"id" => parsed_id}, socket) do
      {:noreply,
       selected_socket
       |> assign(:editing_mode, :sequence_config)
       |> assign(:sequence_panel_data, build_sequence_panel_data(selected_socket, owner))}
    else
      _invalid -> {:noreply, socket}
    end
  end

  def handle_open_sequence_config(_params, socket), do: handle_open_sequence_config(socket)

  @doc """
  Builds the sequence config panel payload (config + tracks + assets).
  Public so collaboration handlers can refresh remote panels in-place.
  """
  @spec build_sequence_panel_data(Socket.t(), map()) :: map() | nil
  def build_sequence_panel_data(_socket, %{type: type}) when type not in ["sequence", "dialogue"], do: nil

  def build_sequence_panel_data(socket, %{type: owner_type, id: owner_id} = owner) do
    project_id = socket.assigns.project.id
    graph = Flows.load_runtime_graph(socket.assigns.flow.id)
    composition = Flows.inspect_node_sequences(owner_id, graph.nodes)
    local_visual_layers = Flows.list_sequence_visual_layers(owner_id)
    local_tracks = Flows.list_sequence_tracks(owner_id)
    visual_layers = effective_visual_layers(composition, owner_id, local_visual_layers)
    removed_visual_layers = removed_visual_layers(composition, owner_id, local_visual_layers)
    tracks = effective_tracks(composition, local_tracks)
    removed_tracks = removed_tracks(composition, local_tracks)

    image_asset_ids =
      selected_asset_ids(local_visual_layers) ++ selected_serialized_asset_ids(visual_layers)

    audio_asset_ids = selected_asset_ids(local_tracks) ++ selected_serialized_asset_ids(tracks)

    %{
      sequence_id: owner_id,
      owner_id: owner_id,
      owner_type: owner_type,
      composition_source_id: owner.composition_source_id,
      composition_sources: composition_source_options(graph.nodes, owner_id),
      config: sequence_config(owner_type, owner_id),
      visual_layers: visual_layers,
      removed_visual_layers: removed_visual_layers,
      tracks: tracks,
      removed_tracks: removed_tracks,
      diagnostics: SequencePresentation.diagnostics(composition),
      image_assets: PickerSearch.initial_asset_options(project_id, "image", Enum.uniq(image_asset_ids)),
      audio_assets: PickerSearch.initial_asset_options(project_id, "audio", Enum.uniq(audio_asset_ids))
    }
  end

  defp sequence_config("sequence", owner_id), do: owner_id |> Flows.get_sequence_config() |> serialize_sequence_config()

  defp sequence_config(_owner_type, _owner_id), do: nil

  defp effective_visual_layers(composition, owner_id, local_layers) do
    local_by_key = Map.new(local_layers, &{&1.layer_key, &1})

    composition
    |> SequencePresentation.inspectable_visual_layers(owner_id)
    |> Enum.map(fn layer ->
      local = Map.get(local_by_key, layer.key)

      Map.merge(layer, %{
        local_row_id: local && local.id,
        overridden_fields: (local && local.overridden_fields) || [],
        inherited: is_nil(local) or layer.origin.inherited
      })
    end)
  end

  defp removed_visual_layers(composition, owner_id, local_layers) do
    local_by_key = Map.new(local_layers, &{&1.layer_key, &1})

    composition
    |> SequencePresentation.inspectable_removed_visual_layers(owner_id)
    |> Enum.map(fn layer ->
      local = Map.get(local_by_key, layer.key)

      Map.merge(layer, %{
        local_row_id: local && local.id,
        overridden_fields: (local && local.overridden_fields) || [],
        inherited: is_nil(local)
      })
    end)
  end

  defp effective_tracks(composition, local_tracks) do
    local_by_key = Map.new(local_tracks, &{&1.track_key, &1})

    composition
    |> SequencePresentation.inspectable_audio_tracks()
    |> Enum.map(fn track ->
      local = Map.get(local_by_key, track.trackKey)

      Map.merge(track, %{
        local_row_id: local && local.id,
        overridden_fields: (local && local.overridden_fields) || [],
        inherited: is_nil(local)
      })
    end)
  end

  defp removed_tracks(composition, local_tracks) do
    local_by_key = Map.new(local_tracks, &{&1.track_key, &1})

    composition
    |> SequencePresentation.inspectable_removed_audio_tracks()
    |> Enum.map(fn track ->
      local = Map.get(local_by_key, track.trackKey)

      Map.merge(track, %{
        local_row_id: local && local.id,
        overridden_fields: (local && local.overridden_fields) || [],
        inherited: is_nil(local)
      })
    end)
  end

  defp composition_source_options(nodes, owner_id) do
    nodes
    |> Map.values()
    |> Enum.filter(fn node ->
      Map.get(node, :type) in ["sequence", "dialogue"] and
        node.id != owner_id and
        valid_composition_source_option?(node, owner_id, nodes)
    end)
    |> Enum.map(fn node ->
      %{id: node.id, type: node.type, label: composition_source_label(node)}
    end)
    |> Enum.sort_by(&{&1.type, String.downcase(&1.label), &1.id})
  end

  defp valid_composition_source_option?(node, owner_id, nodes) do
    composition_source_option_chain_valid?(
      Map.get(node, :composition_source_id),
      owner_id,
      nodes,
      MapSet.new([node.id])
    )
  end

  defp composition_source_option_chain_valid?(nil, _owner_id, _nodes, _visited), do: true
  defp composition_source_option_chain_valid?(owner_id, owner_id, _nodes, _visited), do: false

  defp composition_source_option_chain_valid?(source_id, owner_id, nodes, visited) do
    if MapSet.member?(visited, source_id) do
      false
    else
      case Map.get(nodes, source_id) do
        %{type: type} = source when type in ["sequence", "dialogue"] ->
          composition_source_option_chain_valid?(
            Map.get(source, :composition_source_id),
            owner_id,
            nodes,
            MapSet.put(visited, source_id)
          )

        _missing_or_invalid ->
          false
      end
    end
  end

  defp composition_source_label(%{type: "sequence", sequence_config: config, id: id}) do
    if config && present_string?(config.name), do: config.name, else: "Sequence ##{id}"
  end

  defp composition_source_label(%{type: "dialogue", data: data, id: id}) do
    technical_id = data["technical_id"]
    text = data["text"] |> to_string() |> String.replace(~r/<[^>]*>/, "") |> String.trim()

    cond do
      present_string?(technical_id) -> technical_id
      present_string?(text) -> String.slice(text, 0, 60)
      true -> "Dialogue ##{id}"
    end
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp serialize_sequence_config(nil), do: nil

  defp serialize_sequence_config(%{} = cfg) do
    %{
      name: cfg.name,
      width: cfg.width,
      height: cfg.height
    }
  end

  defp selected_asset_ids(records) do
    records
    |> Enum.map(&Map.get(&1, :asset_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp selected_serialized_asset_ids(records) do
    records
    |> Enum.map(&(Map.get(&1, :asset_id) || Map.get(&1, "asset_id")))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Builds the dialogue panel payload (camelCase shape consumed by
  FlowDialoguePanel.vue). Mirrors `build_sequence_panel_data/2` per D5
  in REFACTOR.md §10. Public so the open-panel handler and
  collaboration refreshes can both call it.

  Returns `nil` if the node is not a dialogue.
  """
  @spec build_dialogue_panel_data(Socket.t(), map()) :: map() | nil
  def build_dialogue_panel_data(_socket, %{type: type}) when type != "dialogue", do: nil

  def build_dialogue_panel_data(socket, %{type: "dialogue"} = node) do
    project_id = socket.assigns.project.id
    data = node.data || %{}

    %{
      nodeId: node.id,
      speakerSheetId: data["speaker_sheet_id"],
      text: data["text"] || "",
      stageDirections: data["stage_directions"] || "",
      menuText: data["menu_text"] || "",
      technicalId: data["technical_id"] || "",
      localizationId: data["localization_id"] || "",
      audioAssetId: data["audio_asset_id"],
      avatarId: data["avatar_id"],
      responses: serialize_dialogue_responses(data["responses"] || []),
      allSheets: Flows.initial_speaker_options(project_id, [data["speaker_sheet_id"]]),
      audioAssets: PickerSearch.initial_asset_options(project_id, "audio", [data["audio_asset_id"]]),
      projectVariables: socket.assigns[:project_variables] || []
    }
  end

  defp serialize_dialogue_responses(responses) when is_list(responses) do
    Enum.map(responses, fn r ->
      %{
        id: r["id"],
        text: r["text"] || "",
        condition: r["condition"],
        instructionAssignments: r["instruction_assignments"] || [],
        hasTypeWarnings: r["has_type_warnings"] || false
      }
    end)
  end

  defp serialize_dialogue_responses(_), do: []

  @spec handle_node_double_clicked(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_node_double_clicked(%{"id" => node_id}, socket) do
    case Flows.get_node(socket.assigns.flow.id, node_id) do
      nil -> {:noreply, socket}
      node -> do_handle_node_double_clicked(node, socket)
    end
  end

  defp do_handle_node_double_clicked(node, socket) do
    editing_mode = NodeTypeRegistry.on_double_click(node.type, node)

    case editing_mode do
      {:navigate, flow_id} ->
        handle_navigate_to_flow(socket, flow_id)

      mode ->
        handle_open_editing_mode(socket, node, to_string(node.id), mode)
    end
  end

  defp handle_navigate_to_flow(socket, flow_id) do
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    flow_id = if is_binary(flow_id), do: flow_id, else: to_string(flow_id)

    {:noreply,
     push_patch(socket,
       to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}"
     )}
  end

  defp handle_open_editing_mode(socket, node, node_id, mode) do
    form = FormHelpers.node_data_to_form(node)
    user = socket.assigns.current_scope.user

    socket =
      if socket.assigns.can_edit do
        handle_node_lock_acquisition(socket, node_id, user)
      else
        socket
      end

    socket =
      socket
      |> assign(:selected_node, node)
      |> assign(:node_form, form)
      |> assign(:editing_mode, mode)

    socket =
      case mode do
        :dialogue_panel -> push_event(socket, "center_on_node", %{id: node_id, sidebar_width: 600})
        :builder -> push_event(socket, "center_on_node", %{id: node_id, sidebar_width: 480})
        _ -> socket
      end

    {:noreply, socket}
  end

  @spec handle_open_sidebar(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_open_sidebar(socket) do
    {:noreply, assign(socket, :editing_mode, :toolbar)}
  end

  @spec handle_close_editor(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_close_editor(socket) do
    # Release the edit lock but keep selected_node set.
    # Clearing selected_node here desynchronises server state from the client's
    # hook.selectedNodeId, which causes the context menu "Open editor panel" to
    # skip sending node_selected (thinking the node is still selected) and then
    # open_dialogue_panel finds selected_node nil → silent failure.
    # The node stays visually selected (toolbar visible); deselect_node clears it.
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:node_form, nil)
     |> assign(:editing_mode, nil)}
  end

  @spec handle_deselect_node(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_deselect_node(socket) do
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)
     |> assign(:editing_mode, nil)
     |> assign(:sequence_panel_data, nil)
     |> assign(:sequence_stage, SequencePresentation.empty_stage())}
  end

  @spec handle_batch_update_positions(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_batch_update_positions(%{"positions" => positions}, socket) when is_list(positions) do
    flow = socket.assigns.flow

    parsed =
      positions
      |> Enum.filter(fn pos ->
        is_integer(pos["id"]) and is_number(pos["position_x"]) and is_number(pos["position_y"])
      end)
      |> Enum.map(fn pos ->
        %{
          id: pos["id"],
          position_x: pos["position_x"] / 1,
          position_y: pos["position_y"] / 1
        }
      end)

    case Flows.batch_update_positions(flow.id, parsed) do
      {:ok, _count} ->
        {:noreply,
         socket
         |> mark_saved()
         |> CollaborationHelpers.broadcast_change(:flow_refresh, %{})}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not update node positions."))}
    end
  end

  def handle_batch_update_positions(_params, socket), do: {:noreply, socket}

  @spec handle_search_available_flows(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_search_available_flows(%{"query" => query}, socket) when is_binary(query) do
    project_id = socket.assigns.project.id
    current_flow_id = socket.assigns.flow.id
    limit = search_limit()

    results = search_flows(socket, project_id, query, exclude_id: current_flow_id)

    {:noreply,
     socket
     |> assign(:available_flows, results)
     |> assign(:flow_search_query, query)
     |> assign(:flow_search_offset, limit)
     |> assign(:flow_search_has_more, length(results) >= limit)}
  end

  def handle_search_available_flows(_params, socket), do: {:noreply, socket}

  @spec handle_toggle_deep_search(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_toggle_deep_search(socket) do
    deep = !socket.assigns[:flow_search_deep]
    socket = assign(socket, :flow_search_deep, deep)

    # Re-run the current search with the new mode
    query = socket.assigns[:flow_search_query] || ""
    handle_search_available_flows(%{"query" => query}, socket)
  end

  @spec handle_search_flows_more(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_search_flows_more(socket) do
    project_id = socket.assigns.project.id
    current_flow_id = socket.assigns.flow.id
    query = socket.assigns[:flow_search_query] || ""
    offset = socket.assigns[:flow_search_offset] || 0
    limit = search_limit()

    more = search_flows(socket, project_id, query, offset: offset, exclude_id: current_flow_id)

    {:noreply,
     socket
     |> assign(:available_flows, (socket.assigns[:available_flows] || []) ++ more)
     |> assign(:flow_search_offset, offset + limit)
     |> assign(:flow_search_has_more, length(more) >= limit)}
  end

  defp search_flows(socket, project_id, query, opts) do
    if socket.assigns[:flow_search_deep],
      do: Flows.search_flows_deep(project_id, query, opts),
      else: Flows.search_flows(project_id, query, opts)
  end

  defp search_limit, do: Flows.default_search_limit()

  @spec handle_node_dragging(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_node_dragging(%{"id" => node_id, "position_x" => x, "position_y" => y}, socket) do
    # Broadcast-only (no DB write) for real-time drag preview on remote clients.
    # No node existence check — JS validates via nodeMap, and auth is required.
    {:noreply,
     CollaborationHelpers.broadcast_change(socket, :node_moved, %{
       node_id: node_id,
       x: x,
       y: y
     })}
  end

  @spec handle_node_moved(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_node_moved(%{"id" => node_id, "position_x" => x, "position_y" => y}, socket) do
    # Use non-raising get_node/2 — the node may have been deleted while a
    # debounced move event was still in flight.
    case Flows.get_node(socket.assigns.flow.id, node_id) do
      nil ->
        {:noreply, socket}

      node ->
        case Flows.update_node_position(node, %{position_x: x, position_y: y}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> mark_saved()
             |> CollaborationHelpers.broadcast_change(:node_moved, %{
               node_id: node_id,
               x: x,
               y: y
             })}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  @spec handle_node_reparented(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_node_reparented(%{"id" => node_id, "parent_id" => parent_id}, socket) do
    with {:ok, parsed_parent} <- parse_optional_int(parent_id),
         node when not is_nil(node) <- Flows.get_node(socket.assigns.flow.id, node_id),
         {:ok, _updated} <- Flows.update_node_parent(node, parsed_parent) do
      {:noreply,
       socket
       |> mark_saved()
       |> CollaborationHelpers.broadcast_change(:node_reparented, %{
         node_id: node_id,
         parent_id: parsed_parent
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  @spec handle_update_sequence_name(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_update_sequence_name(%{"id" => node_id, "name" => name}, socket) when is_binary(name) do
    trimmed = String.trim(name)

    with true <- trimmed != "",
         {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         %{type: "sequence"} = seq <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         {:ok, %{result: updated} = history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.update_sequence(seq, %{"name" => trimmed})
           end) do
      # Keep `node_id` as the integer the client's `nodeMap` uses as key —
      # pushing a stringified id (the shape we receive from pushEvent) would
      # miss the lookup on `handleSequenceRenamed` and leave the local
      # label stale.
      payload = %{node_id: parsed_id, name: updated.sequence_config.name}

      # Push to self so the local editor's `handleSequenceRenamed` bumps
      # `nodeDataVersion` and the header label re-renders immediately.
      # `broadcast_change` below uses `broadcast_from` which skips self, so
      # without this the local label stayed stale until reload.
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "sequence-name")
       |> CollaborationHelpers.push_remote_change_event(:sequence_renamed, payload)
       |> CollaborationHelpers.broadcast_change(:sequence_renamed, payload)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_update_sequence_name(_params, socket), do: {:noreply, socket}

  @doc """
  Updates one or more sequence metadata fields. Visual composition lives
  in sequence visual layers and is handled by dedicated layer events.
  """
  @spec handle_update_sequence_config(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_update_sequence_config(%{"id" => node_id} = params, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         %{type: "sequence"} = seq <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         attrs = extract_sequence_config_attrs(params),
         {:ok, %{result: updated} = history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.update_sequence(seq, attrs)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "sequence-config")
       |> refresh_sequence_editor(parsed_id)
       |> CollaborationHelpers.broadcast_change(:sequence_config_updated, %{
         sequence_id: parsed_id,
         name: updated.sequence_config.name,
         position_x: updated.position_x,
         position_y: updated.position_y,
         width: updated.sequence_config.width,
         height: updated.sequence_config.height
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  defp extract_sequence_config_attrs(params) do
    base = %{"name" => params["name"] || (params["config"] && params["config"]["name"])}

    [
      "position_x",
      "position_y",
      "width",
      "height"
    ]
    |> Enum.reduce(
      base,
      fn field, acc ->
        if Map.has_key?(params, field) do
          Map.put(acc, field, params[field])
        else
          acc
        end
      end
    )
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> ensure_name_fallback(params["id"])
  end

  # `update_sequence`'s config changeset requires :name (existing row satisfies
  # validate_required). When the client sends a partial update without name,
  # attrs may or may not include it. If nothing sent, pull from the current
  # config — changeset cast will no-op if same.
  defp ensure_name_fallback(%{"name" => _} = attrs, _), do: attrs

  defp ensure_name_fallback(attrs, _id), do: attrs

  @doc "Creates a visual layer for the selected sequence."
  @spec handle_create_sequence_visual_layer(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_create_sequence_visual_layer(%{"id" => node_id} = params, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         %{type: type} <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         true <- type in ["sequence", "dialogue"],
         attrs = visual_layer_attrs_from_params(params),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.create_editor_sequence_visual_layer(
               socket.assigns.current_scope,
               socket.assigns.flow,
               parsed_id,
               attrs
             )
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "visual-layer-create")
       |> refresh_sequence_editor(parsed_id)
       |> CollaborationHelpers.broadcast_change(:sequence_visual_layer_changed, %{
         sequence_id: parsed_id
       })}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  @doc "Updates a visual layer for the selected sequence."
  @spec handle_update_sequence_visual_layer(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_update_sequence_visual_layer(%{"id" => node_id, "layer_id" => layer_id} = params, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         {:ok, parsed_layer_id} <- parse_optional_int(layer_id),
         true <- is_integer(parsed_layer_id),
         %{type: type} <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         true <- type in ["sequence", "dialogue"],
         layer when not is_nil(layer) <- Flows.get_sequence_visual_layer(parsed_id, parsed_layer_id),
         attrs = visual_layer_attrs_from_params(params),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.update_editor_sequence_visual_layer(
               socket.assigns.current_scope,
               socket.assigns.flow,
               parsed_id,
               layer,
               attrs
             )
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "visual-layer-#{parsed_layer_id}")
       |> refresh_sequence_editor(parsed_id)
       |> CollaborationHelpers.broadcast_change(:sequence_visual_layer_changed, %{
         sequence_id: parsed_id
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  @doc "Deletes a visual layer for the selected sequence."
  @spec handle_delete_sequence_visual_layer(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_delete_sequence_visual_layer(%{"id" => node_id, "layer_id" => layer_id}, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         {:ok, parsed_layer_id} <- parse_optional_int(layer_id),
         true <- is_integer(parsed_layer_id),
         %{type: type} <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         true <- type in ["sequence", "dialogue"],
         layer when not is_nil(layer) <- Flows.get_sequence_visual_layer(parsed_id, parsed_layer_id),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.delete_sequence_visual_layer(layer)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "visual-layer-#{parsed_layer_id}")
       |> refresh_sequence_editor(parsed_id)
       |> CollaborationHelpers.broadcast_change(:sequence_visual_layer_changed, %{
         sequence_id: parsed_id
       })}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  defp visual_layer_attrs_from_params(params) do
    Enum.reduce(
      [
        "asset_id",
        "kind",
        "label",
        "z_index",
        "slot",
        "x",
        "y",
        "width",
        "height",
        "anchor_x",
        "anchor_y",
        "fit",
        "opacity",
        "visible"
      ],
      %{},
      fn field, acc ->
        if Map.has_key?(params, field), do: Map.put(acc, field, params[field]), else: acc
      end
    )
  end

  @doc """
  Upserts an audio track for the selected sequence. `kind` must be one
  of `music | ambience | sfx`. `asset_id` nullable. `volume` a
  decimal in [0, 1].
  """
  @spec handle_upsert_sequence_track(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_upsert_sequence_track(%{"id" => node_id, "kind" => kind} = params, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         %{type: type} <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         true <- type in ["sequence", "dialogue"],
         attrs = track_attrs_from_params(params),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.upsert_editor_sequence_track(
               socket.assigns.current_scope,
               socket.assigns.flow,
               parsed_id,
               kind,
               attrs
             )
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "audio-track-#{kind}")
       |> refresh_sequence_editor(parsed_id)
       |> CollaborationHelpers.broadcast_change(:sequence_track_upserted, %{
         sequence_id: parsed_id,
         kind: kind
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  defp track_attrs_from_params(params) do
    attrs = %{}

    attrs =
      if Map.has_key?(params, "asset_id"),
        do: Map.put(attrs, "asset_id", params["asset_id"]),
        else: attrs

    attrs =
      case params["volume"] do
        nil -> attrs
        "" -> attrs
        v when is_number(v) -> Map.put(attrs, "volume", Decimal.from_float(v / 1))
        v when is_binary(v) -> maybe_put_decimal_volume(attrs, v)
        _ -> attrs
      end

    attrs
  end

  defp maybe_put_decimal_volume(attrs, value) do
    case Decimal.parse(value) do
      {%Decimal{} = volume, ""} -> Map.put(attrs, "volume", volume)
      _invalid -> attrs
    end
  end

  @doc "Clears the track slot for `(sequence_id, kind)`."
  @spec handle_clear_sequence_track(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_clear_sequence_track(%{"id" => node_id, "kind" => kind}, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         %{type: type} <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         true <- type in ["sequence", "dialogue"],
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.clear_sequence_track(parsed_id, kind)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "audio-track-#{kind}")
       |> refresh_sequence_editor(parsed_id)
       |> CollaborationHelpers.broadcast_change(:sequence_track_cleared, %{
         sequence_id: parsed_id,
         kind: kind
       })}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  @doc "Changes the explicit composition source of a sequence or dialogue."
  def handle_set_composition_source(%{"id" => node_id} = params, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         %{type: type} <- Flows.get_node(socket.assigns.flow.id, parsed_id),
         true <- type in ["sequence", "dialogue"],
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.set_composition_source(parsed_id, params["source_id"])
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "composition-source")
       |> refresh_sequence_editor(parsed_id)
       |> broadcast_composition_change(:sequence_visual_layer_changed, parsed_id, %{})}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  @doc "Overrides selected properties of an effective visual layer."
  def handle_override_sequence_visual_layer(%{"id" => node_id, "layer_key" => layer_key} = params, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         true <- is_binary(layer_key),
         true <- composition_owner_in_current_flow?(socket, parsed_id),
         attrs = visual_layer_attrs_from_params(params),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.override_sequence_visual_layer(parsed_id, layer_key, attrs)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "visual-layer-#{layer_key}")
       |> refresh_sequence_editor(parsed_id)
       |> broadcast_composition_change(:sequence_visual_layer_changed, parsed_id, %{
         layer_key: layer_key
       })}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  @doc "Returns selected visual-layer properties to inheritance."
  def handle_revert_sequence_visual_layer(%{"id" => node_id, "layer_key" => layer_key, "fields" => fields}, socket)
      when is_list(fields) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         true <- is_binary(layer_key),
         true <- composition_owner_in_current_flow?(socket, parsed_id),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.revert_sequence_visual_layer_fields(parsed_id, layer_key, fields)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "visual-layer-#{layer_key}")
       |> refresh_sequence_editor(parsed_id)
       |> broadcast_composition_change(:sequence_visual_layer_changed, parsed_id, %{
         layer_key: layer_key
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  @doc "Removes an effective visual layer for this composition owner."
  def handle_remove_sequence_visual_layer(%{"id" => node_id, "layer_key" => layer_key}, socket) do
    mutate_visual_layer_presence(socket, node_id, layer_key, :remove)
  end

  @doc "Restores a locally removed visual layer."
  def handle_restore_sequence_visual_layer(%{"id" => node_id, "layer_key" => layer_key}, socket) do
    mutate_visual_layer_presence(socket, node_id, layer_key, :restore)
  end

  defp mutate_visual_layer_presence(socket, node_id, layer_key, action) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         true <- is_binary(layer_key),
         true <- composition_owner_in_current_flow?(socket, parsed_id),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             mutate_visual_layer_presence(action, parsed_id, layer_key)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "visual-layer-#{layer_key}")
       |> refresh_sequence_editor(parsed_id)
       |> broadcast_composition_change(:sequence_visual_layer_changed, parsed_id, %{
         layer_key: layer_key
       })}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  defp mutate_visual_layer_presence(:remove, owner_id, layer_key),
    do: Flows.remove_sequence_visual_layer(owner_id, layer_key)

  defp mutate_visual_layer_presence(:restore, owner_id, layer_key),
    do: Flows.restore_sequence_visual_layer(owner_id, layer_key)

  @doc "Overrides selected properties of an effective audio track."
  def handle_override_sequence_track(%{"id" => node_id, "track_key" => track_key} = params, socket) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         true <- is_binary(track_key),
         true <- composition_owner_in_current_flow?(socket, parsed_id),
         attrs = track_attrs_from_params(params),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.override_sequence_track(parsed_id, track_key, attrs)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "audio-track-#{track_key}")
       |> refresh_sequence_editor(parsed_id)
       |> broadcast_composition_change(:sequence_track_upserted, parsed_id, %{
         track_key: track_key
       })}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  @doc "Returns selected audio-track properties to inheritance."
  def handle_revert_sequence_track(%{"id" => node_id, "track_key" => track_key, "fields" => fields}, socket)
      when is_list(fields) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         true <- is_binary(track_key),
         true <- composition_owner_in_current_flow?(socket, parsed_id),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             Flows.revert_sequence_track_fields(parsed_id, track_key, fields)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "audio-track-#{track_key}")
       |> refresh_sequence_editor(parsed_id)
       |> broadcast_composition_change(:sequence_track_upserted, parsed_id, %{
         track_key: track_key
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  @doc "Removes an effective audio track for this composition owner."
  def handle_remove_sequence_track(%{"id" => node_id, "track_key" => track_key}, socket) do
    mutate_track_presence(socket, node_id, track_key, :remove)
  end

  @doc "Restores a locally removed audio track."
  def handle_restore_sequence_track(%{"id" => node_id, "track_key" => track_key}, socket) do
    mutate_track_presence(socket, node_id, track_key, :restore)
  end

  defp mutate_track_presence(socket, node_id, track_key, action) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         true <- is_binary(track_key),
         true <- composition_owner_in_current_flow?(socket, parsed_id),
         {:ok, history} <-
           Flows.transact_sequence_composition(parsed_id, fn ->
             mutate_track_presence(action, parsed_id, track_key)
           end) do
      {:noreply,
       socket
       |> mark_saved()
       |> record_sequence_history(parsed_id, history, "audio-track-#{track_key}")
       |> refresh_sequence_editor(parsed_id)
       |> broadcast_composition_change(:sequence_track_upserted, parsed_id, %{
         track_key: track_key
       })}
    else
      {:error, :composition_dependency_conflict} -> composition_dependency_error(socket)
      _ -> {:noreply, socket}
    end
  end

  defp mutate_track_presence(:remove, owner_id, track_key), do: Flows.remove_sequence_track(owner_id, track_key)

  defp mutate_track_presence(:restore, owner_id, track_key), do: Flows.restore_sequence_track(owner_id, track_key)

  defp record_sequence_history(socket, owner_id, %{previous: previous_snapshot, current: current_snapshot}, history_key) do
    if current_snapshot == previous_snapshot do
      socket
    else
      push_event(socket, "sequence_composition_changed", %{
        owner_id: owner_id,
        history_key: history_key,
        previous: previous_snapshot,
        current: current_snapshot
      })
    end
  end

  @doc "Restores an editor history snapshot without recording a new history action."
  def handle_restore_sequence_composition(
        %{"id" => node_id, "snapshot" => snapshot, "expected_current" => expected_current},
        socket
      )
      when is_map(snapshot) and is_map(expected_current) do
    with {:ok, parsed_id} <- parse_optional_int(node_id),
         true <- is_integer(parsed_id),
         true <- composition_owner_in_current_flow?(socket, parsed_id),
         {:ok, restored} <-
           Flows.restore_sequence_composition(parsed_id, snapshot, expected_current) do
      config = restored["config"] || %{}

      payload = %{
        sequence_id: parsed_id,
        name: config["name"],
        position_x: restored["position_x"],
        position_y: restored["position_y"],
        width: config["width"],
        height: config["height"]
      }

      {:noreply,
       socket
       |> mark_saved()
       |> refresh_sequence_editor(parsed_id)
       |> CollaborationHelpers.push_remote_change_event(:sequence_config_updated, payload)
       |> CollaborationHelpers.broadcast_change(:sequence_config_updated, payload)}
    else
      _invalid ->
        invalidate_sequence_composition_history(socket)
    end
  end

  def handle_restore_sequence_composition(_params, socket), do: invalidate_sequence_composition_history(socket)

  defp invalidate_sequence_composition_history(socket) do
    {:noreply, push_event(socket, "sequence_composition_history_invalidated", %{})}
  end

  @doc false
  def refresh_sequence_editor(socket, owner_id) do
    case Flows.get_node(socket.assigns.flow.id, owner_id) do
      %{type: type} = owner when type in ["sequence", "dialogue"] ->
        graph = Flows.load_runtime_graph(socket.assigns.flow.id)
        speakers_map = FormHelpers.player_speakers_map(socket.assigns.all_sheets)

        socket
        |> maybe_refresh_debug_composition_graph(graph)
        |> maybe_refresh_selected_sequence_surfaces(owner, graph, speakers_map)

      _other ->
        socket
    end
  end

  defp composition_owner_in_current_flow?(socket, owner_id) do
    match?(
      %{type: type} when type in ["sequence", "dialogue"],
      Flows.get_node(socket.assigns.flow.id, owner_id)
    )
  end

  defp maybe_refresh_selected_owner(socket, %{id: owner_id} = owner) do
    case socket.assigns[:selected_node] do
      %{id: ^owner_id} -> assign(socket, :selected_node, owner)
      _other -> socket
    end
  end

  defp maybe_refresh_selected_sequence_surfaces(
         %{assigns: %{selected_node: %{id: owner_id}}} = socket,
         %{id: owner_id} = owner,
         graph,
         speakers_map
       ) do
    socket
    |> maybe_refresh_selected_owner(owner)
    |> assign(
      :sequence_stage,
      SequencePresentation.stage(
        owner.id,
        graph.nodes,
        speakers_map,
        socket.assigns.project.id,
        nil,
        SequencePresentation.locale_context(socket.assigns)
      )
    )
    |> maybe_refresh_sequence_panel(owner)
  end

  defp maybe_refresh_selected_sequence_surfaces(socket, _owner, _graph, _speakers_map), do: socket

  defp maybe_refresh_debug_composition_graph(
         %{assigns: %{debug_panel_open: true, debug_state: %{current_flow_id: flow_id}, flow: %{id: flow_id}}} = socket,
         graph
       ) do
    presented = DebugExecutionHandlers.present_runtime_graph(graph)

    socket
    |> assign(:debug_nodes, presented.nodes)
    |> assign(:debug_connections, presented.connections)
  end

  defp maybe_refresh_debug_composition_graph(socket, _graph), do: socket

  defp maybe_refresh_sequence_panel(socket, owner) do
    if socket.assigns[:editing_mode] == :sequence_config,
      do: assign(socket, :sequence_panel_data, build_sequence_panel_data(socket, owner)),
      else: socket
  end

  defp broadcast_composition_change(socket, action, owner_id, payload) do
    CollaborationHelpers.broadcast_change(
      socket,
      action,
      Map.merge(%{sequence_id: owner_id}, payload)
    )
  end

  # Accepts nil, integer, or a string that parses cleanly to an integer.
  # Anything else returns :error so the handler can no-op.
  defp parse_optional_int(nil), do: {:ok, nil}
  defp parse_optional_int(i) when is_integer(i), do: {:ok, i}

  defp parse_optional_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> {:ok, i}
      _ -> :error
    end
  end

  defp parse_optional_int(_), do: :error

  @spec handle_update_node_data(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_update_node_data(%{"node" => node_params}, socket) do
    NodeHelpers.update_node_data(socket, node_params)
  end

  @spec handle_update_node_text(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_update_node_text(%{"id" => node_id, "content" => content}, socket) do
    NodeHelpers.update_node_text(socket, node_id, content)
  end

  @spec handle_mention_suggestions(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_mention_suggestions(%{"query" => query}, socket) do
    project_id = socket.assigns.project.id
    results = Flows.search_mentions(project_id, query)

    items =
      Enum.map(results, fn result ->
        %{
          id: result.id,
          type: result.type,
          name: result.name,
          shortcut: result.shortcut,
          label: result.shortcut || result.name
        }
      end)

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: items})}
  end

  @spec handle_delete_node(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_delete_node(%{"id" => node_id}, socket) do
    NodeHelpers.delete_node(socket, node_id)
  end

  @spec handle_duplicate_node(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_duplicate_node(%{"id" => node_id}, socket) do
    NodeHelpers.duplicate_node(socket, node_id)
  end

  @spec handle_update_node_field(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_update_node_field(%{"field" => field, "value" => value}, socket) do
    node = socket.assigns.selected_node

    if node do
      NodeHelpers.update_node_field(socket, node.id, field, value)
    else
      {:noreply, socket}
    end
  end

  # Private helpers

  defp composition_dependency_error(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext(
         "flows",
         "This composition or one of its descendants still depends on that source, layer, or audio track. Reassign or revert those local changes first."
       )
     )}
  end

  defp format_shortcut_error(%Ecto.Changeset{} = changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> dgettext("flows", "Shortcut %{error}", error: msg)
      nil -> dgettext("flows", "Could not save shortcut.")
    end
  end

  defp format_shortcut_error(_reason), do: dgettext("flows", "Could not save shortcut.")

  @lock_heartbeat_interval 10_000

  defp handle_node_lock_acquisition(socket, node_id, user) do
    alias Storyarn.Platform.Collaboration

    scope = {:flow, socket.assigns.flow.id}

    case Collaboration.acquire_lock(scope, node_id, user) do
      {:ok, _lock_info} ->
        CollaborationHelpers.broadcast_lock_change(socket, :node_locked, node_id)
        node_locks = Collaboration.list_locks(scope)

        # Cancel any existing heartbeat and start a new one
        cancel_lock_heartbeat(socket)
        ref = Process.send_after(self(), :refresh_node_lock, @lock_heartbeat_interval)

        socket
        |> assign(:node_locks, node_locks)
        |> assign(:locked_node_id, node_id)
        |> assign(:lock_heartbeat_ref, ref)
        |> push_event("locks_updated", %{locks: node_locks})

      {:error, :already_locked, lock_info} ->
        put_flash(
          socket,
          :info,
          dgettext("flows", "This node is being edited by %{user}",
            user: FormHelpers.get_email_name(lock_info.user_email)
          )
        )
    end
  end

  defp release_node_lock(socket, node_id) do
    alias Storyarn.Platform.Collaboration

    scope = {:flow, socket.assigns.flow.id}
    user_id = socket.assigns.current_scope.user.id

    cancel_lock_heartbeat(socket)
    Collaboration.release_lock(scope, node_id, user_id)
    CollaborationHelpers.broadcast_lock_change(socket, :node_unlocked, node_id)
    node_locks = Collaboration.list_locks(scope)

    socket
    |> assign(:node_locks, node_locks)
    |> assign(:locked_node_id, nil)
    |> assign(:lock_heartbeat_ref, nil)
    |> push_event("locks_updated", %{locks: node_locks})
  end

  defp cancel_lock_heartbeat(socket) do
    if ref = socket.assigns[:lock_heartbeat_ref] do
      Process.cancel_timer(ref)
    end
  end
end
