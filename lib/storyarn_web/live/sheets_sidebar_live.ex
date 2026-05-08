defmodule StoryarnWeb.SheetsSidebarLive do
  @moduledoc """
  Sheets-specific left sidebar LiveView.

  Rendered as a sticky nested child of `ProjectShell` on sheet routes.
  Owns the sheets tree + tree mutations. Other tools get their own
  sidebar LV (e.g. `LocalizationSidebarLive`). Tool-specific toolbar
  extras render via the `:top_bar_extras_right` slot of `ProjectShell`
  from each page LV.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.PropsSerializer

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]
    if locale = session["locale"], do: Gettext.put_locale(Storyarn.Gettext, locale)
    project_id = session["project_id"]

    project =
      if project_id && current_scope do
        case Projects.get_project(current_scope, project_id) do
          {:ok, project, _membership} -> project
          _ -> nil
        end
      end

    dashboard_mode = is_nil(session["sheet_id"])

    socket =
      socket
      |> assign(:current_scope, current_scope)
      |> assign(:project, project)
      |> assign(:project_id, project_id)
      |> assign(:workspace_slug, session["workspace_slug"])
      |> assign(:project_slug, session["project_slug"])
      |> assign(:sheet_id, session["sheet_id"])
      |> assign(:can_edit, session["can_edit"] || false)
      |> assign(:active_tool, session["active_tool"] || "sheets")
      |> assign(:dashboard_url, session["dashboard_url"])
      |> assign(:dashboard_mode, dashboard_mode)
      |> assign(:main_sidebar_open, dashboard_mode)
      |> assign(:main_sidebar_pinned, dashboard_mode)
      |> assign(:pending_delete_id, nil)
      |> assign(:sheets_tree, load_sheets_tree(project_id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, shell_topic(project_id))
      Collaboration.subscribe_changes({:project, project_id})
    end

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.vue
        v-component="modules/sheets/navigation/SheetsSidebar"
        v-socket={@socket}
        id="shell-main-sidebar"
        main-sidebar-open={@main_sidebar_open}
        main-sidebar-pinned={@main_sidebar_pinned}
        show-pin={not is_nil(@sheet_id)}
        active-tool={@active_tool}
        dashboard-url={@dashboard_url}
        on-dashboard={is_nil(@sheet_id)}
        sidebar-props={
          %{
            sheetsTree: @sheets_tree,
            canEdit: @can_edit,
            workspaceSlug: @workspace_slug,
            projectSlug: @project_slug,
            selectedSheetId: @sheet_id
          }
        }
      />
    </div>
    """
  end

  # ── Panel state events from SidebarFrame.vue ────────────────────────────────
  @impl true
  def handle_event("main_sidebar_init", _params, %{assigns: %{dashboard_mode: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("main_sidebar_init", %{"pinned" => pinned}, socket) do
    {:noreply,
     socket
     |> assign(:main_sidebar_pinned, pinned)
     |> assign(:main_sidebar_open, pinned)}
  end

  def handle_event("main_sidebar_toggle", _params, %{assigns: %{dashboard_mode: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("main_sidebar_toggle", _params, socket) do
    {:noreply, assign(socket, :main_sidebar_open, !socket.assigns.main_sidebar_open)}
  end

  def handle_event("main_sidebar_pin", _params, socket) do
    pinned = !socket.assigns.main_sidebar_pinned

    {:noreply,
     socket
     |> assign(:main_sidebar_pinned, pinned)
     |> assign(:main_sidebar_open, pinned)}
  end

  # ── Tree mutations ────────────────────────────────────────────────────────
  def handle_event("create_sheet", _params, socket) do
    with_edit(socket, fn socket ->
      case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("sheets", "Untitled")}) do
        {:ok, new_sheet} ->
          {:noreply, on_tree_change_and_open(socket, new_sheet.id)}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  def handle_event("create_child_sheet", %{"parent_id" => parent_id}, socket) do
    with_edit(socket, fn socket ->
      attrs = %{name: dgettext("sheets", "New Sheet"), parent_id: parent_id}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          {:noreply, on_tree_change_and_open(socket, new_sheet.id)}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  def handle_event("set_pending_delete_sheet", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_sheet", _params, socket) do
    with_edit(socket, fn socket ->
      case socket.assigns.pending_delete_id do
        nil ->
          {:noreply, socket}

        id ->
          with %{} = sheet <- Sheets.get_sheet(socket.assigns.project.id, id),
               {:ok, _} <- Sheets.delete_sheet(sheet) do
            broadcast_entity_deleted(socket, id)

            {:noreply,
             socket
             |> assign(:pending_delete_id, nil)
             |> put_flash(:info, dgettext("sheets", "Sheet moved to trash."))
             |> refresh_tree_and_broadcast()}
          else
            _ ->
              {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete sheet."))}
          end
      end
    end)
  end

  def handle_event("move_to_parent", params, socket) do
    with_edit(socket, fn socket ->
      %{"item_id" => id, "new_parent_id" => new_parent_id, "position" => position} = params

      sheet = Sheets.get_sheet(socket.assigns.project.id, MapUtils.parse_int(id))

      if sheet do
        parsed_parent =
          if new_parent_id in [nil, ""], do: nil, else: MapUtils.parse_int(new_parent_id)

        parsed_pos = MapUtils.parse_int(position) || 0

        case Sheets.move_sheet_to_position(sheet, parsed_parent, parsed_pos) do
          {:ok, _} ->
            {:noreply, refresh_tree_and_broadcast(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not move sheet."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  # ── Shell → sidebar synchronization ───────────────────────────────────────
  @impl true
  def handle_info({:active_sheet, sheet_id}, socket) do
    {:noreply, assign(socket, :sheet_id, sheet_id)}
  end

  def handle_info({:tree_changed, :sheets}, socket) do
    {:noreply, assign(socket, :sheets_tree, load_sheets_tree(socket.assigns.project_id))}
  end

  # Remote collaboration changes (from other clients) that affect the tree
  # shape or sheet names. Reload local tree to stay in sync.
  def handle_info({:remote_change, action, _payload}, socket)
      when action in [:tree_changed, :sheet_updated, :sheet_restored] do
    {:noreply, assign(socket, :sheets_tree, load_sheets_tree(socket.assigns.project_id))}
  end

  def handle_info({:remote_change, _action, _payload}, socket), do: {:noreply, socket}

  # Forwarded from ToolbarsLive (LeftToolbar.vue's pushEvent lands there).
  def handle_info({:toolbar_event, "main_sidebar_toggle", _params}, socket) do
    {:noreply, assign(socket, :main_sidebar_open, !socket.assigns.main_sidebar_open)}
  end

  def handle_info({:toolbar_event, "main_sidebar_pin", _params}, socket) do
    pinned = !socket.assigns.main_sidebar_pinned

    {:noreply,
     socket
     |> assign(:main_sidebar_pinned, pinned)
     |> assign(:main_sidebar_open, pinned)}
  end

  def handle_info({:toolbar_event, "main_sidebar_init", %{"pinned" => pinned}}, socket) do
    {:noreply,
     socket
     |> assign(:main_sidebar_pinned, pinned)
     |> assign(:main_sidebar_open, pinned)}
  end

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────
  defp with_edit(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("You don't have permission to edit."))}
    end
  end

  defp refresh_tree_and_broadcast(socket) do
    socket = assign(socket, :sheets_tree, load_sheets_tree(socket.assigns.project_id))

    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      shell_topic(socket.assigns.project_id),
      {:tree_changed, :sheets}
    )

    socket
  end

  defp broadcast_entity_deleted(socket, id) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      shell_topic(socket.assigns.project_id),
      {:entity_deleted, id}
    )
  end

  defp on_tree_change_and_open(socket, new_sheet_id) do
    socket = refresh_tree_and_broadcast(socket)

    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      shell_topic(socket.assigns.project_id),
      {:open_sheet, new_sheet_id}
    )

    socket
  end

  defp load_sheets_tree(nil), do: []

  defp load_sheets_tree(project_id) do
    project_id
    |> Sheets.list_sheets_tree()
    |> PropsSerializer.prepare_tree()
  end

  def shell_topic(project_id), do: "project:#{project_id}:shell"
end
