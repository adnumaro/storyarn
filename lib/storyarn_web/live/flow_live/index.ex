defmodule StoryarnWeb.FlowLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      flows={@flows}
      active_tool={:flows}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
      can_edit={@can_edit}
    >
      <div class="max-w-4xl mx-auto">
        <.header>
          {gettext("Flows")}
          <:subtitle>
            {gettext("Create visual narrative flows and dialogue trees")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <.link
              patch={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/new"}
              class="btn btn-primary"
            >
              <.icon name="plus" class="size-4 mr-2" />
              {gettext("New Flow")}
            </.link>
          </:actions>
        </.header>

        <.empty_state :if={@flows == []} icon="git-branch">
          {gettext("No flows yet. Create your first flow to get started.")}
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
          :if={@live_action == :new}
          id="new-flow-modal"
          show
          on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows")}
        >
          <.live_component
            module={StoryarnWeb.FlowLive.Form}
            id="new-flow-form"
            project={@project}
            title={gettext("New Flow")}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
          />
        </.modal>
      </div>
    </Layouts.project>
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
                  title={gettext("Main flow")}
                >
                  {gettext("Main")}
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
                  {gettext("Set as main")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  class="text-error"
                  phx-click="delete"
                  phx-value-id={@flow.id}
                  data-confirm={gettext("Are you sure you want to delete this flow?")}
                  onclick="event.stopPropagation();"
                >
                  <.icon name="trash-2" class="size-4" />
                  {gettext("Delete")}
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
        project = Repo.preload(project, :workspace)
        flows = Flows.list_flows(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:flows, flows)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
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
     |> put_flash(:info, gettext("Flow created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow.id}"
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => flow_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

        case Flows.delete_flow(flow) do
          {:ok, _} ->
            flows = Flows.list_flows(socket.assigns.project.id)

            {:noreply,
             socket
             |> put_flash(:info, gettext("Flow deleted successfully."))
             |> assign(:flows, flows)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete flow."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("set_main", %{"id" => flow_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

        case Flows.set_main_flow(flow) do
          {:ok, _} ->
            flows = Flows.list_flows(socket.assigns.project.id)

            {:noreply,
             socket
             |> put_flash(:info, gettext("Flow set as main."))
             |> assign(:flows, flows)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not set main flow."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end
end
