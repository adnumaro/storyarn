defmodule StoryarnWeb.Live.Shared.TreePanelHandlers do
  @moduledoc """
  Shared event handlers for the focus layout tree panel.

  Import this module in any LiveView that uses `Layouts.focus` to get
  tree panel toggle, pin, and tool switching event handlers.

  ## Usage

      import StoryarnWeb.Live.Shared.TreePanelHandlers

  Then delegate in `handle_event/3`:

      def handle_event("tree_panel_" <> _ = event, params, socket),
        do: handle_tree_panel_event(event, params, socket)

      def handle_event("switch_tool", params, socket),
        do: handle_tree_panel_event("switch_tool", params, socket)

      def handle_event("tree_panel_init", params, socket),
        do: handle_tree_panel_event("tree_panel_init", params, socket)

  ## Required assigns

  The socket must have these assigns set in mount:
  - `:tree_panel_open` (boolean)
  - `:tree_panel_pinned` (boolean)
  """

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Handles tree panel events. Call from your LiveView's handle_event/3.
  """
  def handle_tree_panel_event("tree_panel_init", %{"pinned" => pinned}, socket) do
    # The JS hook reports the localStorage-persisted pin state.
    # If pinned, also open the panel (server starts closed to avoid flash).
    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  def handle_tree_panel_event("tree_panel_toggle", _params, socket) do
    open = !socket.assigns.tree_panel_open

    {:noreply, assign(socket, :tree_panel_open, open)}
  end

  def handle_tree_panel_event("tree_panel_pin", _params, socket) do
    pinned = !socket.assigns.tree_panel_pinned

    # Unpinning closes the panel; pinning keeps it as-is
    open = if pinned, do: socket.assigns.tree_panel_open, else: false

    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, open)}
  end

  @doc """
  Returns default focus layout assigns to merge in mount.

  ## Example

      socket
      |> assign(focus_layout_defaults())
      |> assign(:active_tool, :sheets)
  """
  def focus_layout_defaults do
    [
      tree_panel_open: false,
      tree_panel_pinned: false,
      online_users: []
    ]
  end

  # ===========================================================================
  # Generic Tree CRUD Handlers
  # ===========================================================================

  @doc """
  Sets the pending delete ID on the socket.

  Used by all tree sidebar delete confirmation flows.

  ## Example

      def handle_event("set_pending_delete_sheet", %{"id" => id}, socket) do
        TreePanelHandlers.handle_set_pending_delete(socket, id)
      end
  """
  def handle_set_pending_delete(socket, id) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  @doc """
  Confirms a pending delete by calling `delete_fn` with the pending ID.

  If no pending delete ID is set, returns `{:noreply, socket}` unchanged.

  `delete_fn` receives `(socket, id)` and must return `{:noreply, socket}`.

  ## Example

      def handle_event("confirm_delete_sheet", _params, socket) do
        TreePanelHandlers.handle_confirm_delete(socket, &SheetTreeHelpers.delete_sheet/2)
      end
  """
  def handle_confirm_delete(socket, delete_fn) do
    if id = socket.assigns[:pending_delete_id] do
      socket = assign(socket, :pending_delete_id, nil)
      delete_fn.(socket, id)
    else
      {:noreply, socket}
    end
  end

  @doc """
  Creates an entity and navigates to it.

  `create_fn` receives `(project, attrs)` and returns `{:ok, entity}` or `{:error, changeset}`.
  `path_fn` receives `(socket, entity)` and returns the path string.
  `error_msg` is the flash message on failure.

  ## Example

      def handle_event("create_flow", _params, socket) do
        with_authorization(socket, :edit_content, fn _socket ->
          TreePanelHandlers.handle_create_entity(socket,
            %{name: dgettext("flows", "Untitled")},
            &Flows.create_flow/2,
            &flow_path/2,
            dgettext("flows", "Could not create flow.")
          )
        end)
      end
  """
  def handle_create_entity(socket, attrs, create_fn, path_fn, error_msg, opts \\ []) do
    case create_fn.(socket.assigns.project, attrs) do
      {:ok, entity} ->
        push_fn =
          if Keyword.get(opts, :patch, false),
            do: &Phoenix.LiveView.push_patch/2,
            else: &Phoenix.LiveView.push_navigate/2

        socket =
          case Keyword.get(opts, :reload_tree_fn) do
            nil -> socket
            reload_fn -> reload_fn.(socket)
          end

        {:noreply, push_fn.(socket, to: path_fn.(socket, entity))}

      {:error, _changeset} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, error_msg)}
    end
  end

  @doc """
  Creates a child entity under a parent and navigates to it.

  Merges `%{parent_id: parent_id}` into `attrs` before calling `create_fn`.

  ## Example

      def handle_event("create_child_flow", %{"parent-id" => parent_id}, socket) do
        with_authorization(socket, :edit_content, fn _socket ->
          TreePanelHandlers.handle_create_child(socket, parent_id,
            %{name: dgettext("flows", "Untitled")},
            &Flows.create_flow/2,
            &flow_path/2,
            dgettext("flows", "Could not create flow.")
          )
        end)
      end
  """
  def handle_create_child(socket, parent_id, attrs, create_fn, path_fn, error_msg, opts \\ []) do
    handle_create_entity(
      socket,
      Map.put(attrs, :parent_id, parent_id),
      create_fn,
      path_fn,
      error_msg,
      opts
    )
  end

  @doc """
  Deletes an entity and handles navigation/tree reload.

  If the deleted entity is the currently viewed one (matched via `current_entity_id`),
  navigates to `index_path`. Otherwise, reloads the tree via `reload_tree_fn`.

  `get_fn` receives `(project_id, entity_id)` and returns the entity or nil.
  `delete_fn` receives `(entity)` and returns `{:ok, _}` or `{:error, _}`.
  `reload_tree_fn` receives `(socket)` and returns an updated socket.

  ## Options

    * `:success_msg` - flash message on success (default: none)
    * `:error_msg` - flash message on failure (required)
    * `:not_found_msg` - flash message when entity not found (optional, returns socket unchanged if nil)

  ## Example

      def handle_event("delete_flow", %{"id" => flow_id}, socket) do
        with_authorization(socket, :edit_content, fn _socket ->
          TreePanelHandlers.handle_delete_entity(socket, flow_id,
            current_entity_id: socket.assigns.flow.id,
            get_fn: &Flows.get_flow!/2,
            delete_fn: &Flows.delete_flow/1,
            index_path: ~p"/workspaces/...",
            reload_tree_fn: &reload_flows_tree/1,
            success_msg: dgettext("flows", "Flow moved to trash."),
            error_msg: dgettext("flows", "Could not delete flow.")
          )
        end)
      end
  """
  def handle_delete_entity(socket, entity_id, opts) do
    get_fn = Keyword.fetch!(opts, :get_fn)
    delete_fn = Keyword.fetch!(opts, :delete_fn)
    current_entity_id = Keyword.fetch!(opts, :current_entity_id)
    index_path = Keyword.fetch!(opts, :index_path)
    reload_tree_fn = Keyword.fetch!(opts, :reload_tree_fn)
    error_msg = Keyword.fetch!(opts, :error_msg)
    success_msg = Keyword.get(opts, :success_msg)
    not_found_msg = Keyword.get(opts, :not_found_msg)

    entity = get_fn.(socket.assigns.project.id, entity_id)

    cond do
      is_nil(entity) && not_found_msg ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, not_found_msg)}

      is_nil(entity) ->
        {:noreply, socket}

      true ->
        do_delete_entity(socket, entity, entity_id, delete_fn,
          current_entity_id: current_entity_id,
          index_path: index_path,
          reload_tree_fn: reload_tree_fn,
          success_msg: success_msg,
          error_msg: error_msg
        )
    end
  end

  defp do_delete_entity(socket, entity, entity_id, delete_fn, opts) do
    case delete_fn.(entity) do
      {:ok, _} ->
        socket =
          if opts[:success_msg],
            do: Phoenix.LiveView.put_flash(socket, :info, opts[:success_msg]),
            else: socket

        if to_string(entity_id) == to_string(opts[:current_entity_id]) do
          {:noreply, Phoenix.LiveView.push_navigate(socket, to: opts[:index_path])}
        else
          {:noreply, opts[:reload_tree_fn].(socket)}
        end

      {:error, _} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, opts[:error_msg])}
    end
  end

  @doc """
  Moves an entity to a new parent position in the tree.

  Parses `new_parent_id` and `position` from strings, then calls `move_fn`.
  On success, reloads the tree via `reload_tree_fn`.

  `get_fn` receives `(project_id, entity_id)` and returns the entity or nil.
  `move_fn` receives `(entity, new_parent_id, position)` and returns `{:ok, _}` or `{:error, _}`.
  `reload_tree_fn` receives `(socket)` and returns an updated socket.

  ## Example

      def handle_event("move_to_parent", %{"item_id" => id, ...}, socket) do
        with_authorization(socket, :edit_content, fn _socket ->
          TreePanelHandlers.handle_move_entity(socket, id, new_parent_id, position,
            get_fn: &Flows.get_flow!/2,
            move_fn: &Flows.move_flow_to_position/3,
            reload_tree_fn: &reload_flows_tree/1,
            error_msg: dgettext("flows", "Could not move flow.")
          )
        end)
      end
  """
  def handle_move_entity(socket, entity_id, new_parent_id, position, opts) do
    get_fn = Keyword.fetch!(opts, :get_fn)
    move_fn = Keyword.fetch!(opts, :move_fn)
    reload_tree_fn = Keyword.fetch!(opts, :reload_tree_fn)
    error_msg = Keyword.fetch!(opts, :error_msg)

    entity = get_fn.(socket.assigns.project.id, entity_id)
    new_parent_id = Storyarn.Shared.MapUtils.parse_int(new_parent_id)
    position = Storyarn.Shared.MapUtils.parse_int(position) || 0

    case move_fn.(entity, new_parent_id, position) do
      {:ok, _} ->
        {:noreply, reload_tree_fn.(socket)}

      {:error, _} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, error_msg)}
    end
  end
end
