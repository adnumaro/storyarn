defmodule StoryarnWeb.FlowLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.Sidebar.FlowTree

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
    >
      <:tree_content>
        <FlowTree.flows_section
          flows_tree={@flows_tree}
          workspace={@workspace}
          project={@project}
          can_edit={@can_edit}
        />
      </:tree_content>
      <div class="max-w-4xl mx-auto">
        <.header>
          {dgettext("flows", "Flows")}
          <:subtitle>
            {dgettext("flows", "Create visual narrative flows and dialogue trees")}
          </:subtitle>
        </.header>

        <.empty_state :if={@flows == []} icon="git-branch">
          {dgettext("flows", "No flows yet. Create your first flow to get started.")}
        </.empty_state>

        <div :if={@flows != []} class="mt-6 space-y-2">
          <.flow_card
            :for={flow <- @flows}
            flow={flow}
            project={@project}
            workspace={@workspace}
            can_edit={@can_edit}
          />
        </div>

        <.modal
          :if={@live_action == :new and @can_edit}
          id="new-flow-modal"
          show
          on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows")}
        >
          <.live_component
            module={StoryarnWeb.FlowLive.Form}
            id="new-flow-form"
            project={@project}
            title={dgettext("flows", "New Flow")}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
          />
        </.modal>

        <.confirm_modal
          :if={@can_edit}
          id="delete-flow-confirm"
          title={dgettext("flows", "Delete flow?")}
          message={dgettext("flows", "Are you sure you want to delete this flow?")}
          confirm_text={dgettext("flows", "Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete")}
        />
      </div>
    </Layouts.focus>
    """
  end

  attr :flow, :map, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :can_edit, :boolean, default: false

  defp flow_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow">
      <div class="card-body p-4">
        <div class="flex items-center justify-between">
          <.link
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}"}
            class="flex items-center gap-3 flex-1 min-w-0"
          >
            <div class="rounded-lg bg-primary/10 p-2">
              <.icon name="git-branch" class="size-5 text-primary" />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="font-medium truncate flex items-center gap-2">
                {@flow.name}
                <span
                  :if={@flow.is_main}
                  class="badge badge-primary badge-xs"
                  title={dgettext("flows", "Main flow")}
                >
                  {dgettext("flows", "Main")}
                </span>
              </h3>
              <p :if={@flow.description} class="text-sm text-base-content/60 truncate">
                {@flow.description}
              </p>
            </div>
          </.link>
          <div :if={@can_edit} class="dropdown dropdown-end">
            <button
              type="button"
              tabindex="0"
              class="btn btn-ghost btn-sm btn-square"
              onclick="event.stopPropagation();"
            >
              <.icon name="more-horizontal" class="size-4" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
            >
              <li :if={!@flow.is_main}>
                <button
                  type="button"
                  phx-click="set_main"
                  phx-value-id={@flow.id}
                  onclick="event.stopPropagation();"
                >
                  <.icon name="star" class="size-4" />
                  {dgettext("flows", "Set as main")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  class="text-error"
                  phx-click={
                    JS.push("set_pending_delete", value: %{id: @flow.id})
                    |> show_modal("delete-flow-confirm")
                  }
                  onclick="event.stopPropagation();"
                >
                  <.icon name="trash-2" class="size-4" />
                  {dgettext("flows", "Delete")}
                </button>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        flows = Flows.list_flows(project.id)
        flows_tree = Flows.list_flows_tree(project.id)
        can_edit = Projects.can?(membership.role, :edit_content)

        # Leaving the flow editor — clear navigation history for this user/project
        user_id = socket.assigns.current_scope.user.id
        Flows.nav_history_clear({user_id, project.id})

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:flows, flows)
          |> assign(:flows_tree, flows_tree)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({StoryarnWeb.FlowLive.Form, {:saved, flow}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, dgettext("flows", "Flow created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow.id}"
     )}
  end

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("set_pending_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("set_pending_delete_flow", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_delete_flow", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => flow_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

      case Flows.delete_flow(flow) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("flows", "Flow moved to trash."))
           |> reload_flows()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not delete flow."))}
      end
    end)
  end

  def handle_event("delete_flow", %{"id" => flow_id}, socket) do
    handle_event("delete", %{"id" => flow_id}, socket)
  end

  def handle_event("set_main", %{"id" => flow_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

      case Flows.set_main_flow(flow) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("flows", "Flow set as main."))
           |> reload_flows()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not set main flow."))}
      end
    end)
  end

  def handle_event("set_main_flow", %{"id" => flow_id}, socket) do
    handle_event("set_main", %{"id" => flow_id}, socket)
  end

  def handle_event("create_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      case Flows.create_flow(socket.assigns.project, %{name: dgettext("flows", "Untitled")}) do
        {:ok, new_flow} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event("create_child_flow", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("flows", "Untitled"), parent_id: parent_id}

      case Flows.create_flow(socket.assigns.project, attrs) do
        {:ok, new_flow} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    with_authorization(socket, :edit_content, fn socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, item_id)
      new_parent_id = MapUtils.parse_int(new_parent_id)
      position = MapUtils.parse_int(position) || 0

      case Flows.move_flow_to_position(flow, new_parent_id, position) do
        {:ok, _} ->
          {:noreply, reload_flows(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not move flow."))}
      end
    end)
  end

  def handle_event("create_sheet", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("flows", "Untitled")}) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create sheet."))}
      end
    end)
  end

  # Helper to reload flows after changes
  defp reload_flows(socket) do
    project_id = socket.assigns.project.id

    socket
    |> assign(:flows, Flows.list_flows(project_id))
    |> assign(:flows_tree, Flows.list_flows_tree(project_id))
  end
end
