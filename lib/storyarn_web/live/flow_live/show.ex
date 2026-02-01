defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  import StoryarnWeb.Layouts, only: [flash_group: 1]

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Projects
  alias Storyarn.Repo

  @node_types FlowNode.node_types()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <%!-- Header --%>
      <header class="navbar bg-base-100 border-b border-base-300 px-4 shrink-0">
        <div class="flex-none">
          <.link
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="chevron-left" class="size-4" />
            {gettext("Flows")}
          </.link>
        </div>
        <div class="flex-1 flex items-center gap-3 ml-4">
          <h1 class="text-lg font-medium">{@flow.name}</h1>
          <span
            :if={@flow.is_main}
            class="badge badge-primary badge-sm"
            title={gettext("Main flow")}
          >
            {gettext("Main")}
          </span>
        </div>
        <div :if={@can_edit} class="flex-none flex items-center gap-2">
          <.save_indicator status={@save_status} />
          <div class="dropdown dropdown-end">
            <button type="button" tabindex="0" class="btn btn-primary btn-sm gap-2">
              <.icon name="plus" class="size-4" />
              {gettext("Add Node")}
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-48 z-50 mt-2"
            >
              <li :for={type <- @node_types}>
                <button type="button" phx-click="add_node" phx-value-type={type}>
                  <.node_type_icon type={type} />
                  {node_type_label(type)}
                </button>
              </li>
            </ul>
          </div>
        </div>
      </header>

      <%!-- Main content: Canvas + Properties Panel --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Canvas --%>
        <div class="flex-1 relative bg-base-200">
          <div
            id="flow-canvas"
            phx-hook="FlowCanvas"
            phx-update="ignore"
            class="absolute inset-0"
            data-flow={Jason.encode!(@flow_data)}
          >
          </div>
        </div>

        <%!-- Properties Panel --%>
        <aside
          :if={@selected_node}
          class="w-80 bg-base-100 border-l border-base-300 flex flex-col overflow-hidden"
        >
          <div class="p-4 border-b border-base-300 flex items-center justify-between">
            <h2 class="font-medium flex items-center gap-2">
              <.node_type_icon type={@selected_node.type} />
              {node_type_label(@selected_node.type)}
            </h2>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square"
              phx-click="deselect_node"
            >
              <.icon name="x" class="size-4" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-4">
            <.node_properties_form
              node={@selected_node}
              form={@node_form}
              can_edit={@can_edit}
            />
          </div>

          <div :if={@can_edit} class="p-4 border-t border-base-300">
            <button
              type="button"
              class="btn btn-error btn-outline btn-sm w-full"
              phx-click="delete_node"
              phx-value-id={@selected_node.id}
              data-confirm={gettext("Are you sure you want to delete this node?")}
            >
              <.icon name="trash-2" class="size-4 mr-2" />
              {gettext("Delete Node")}
            </button>
          </div>
        </aside>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :status, :atom, required: true

  defp save_indicator(assigns) do
    ~H"""
    <div :if={@status != :idle} class="flex items-center gap-2 text-sm">
      <span :if={@status == :saving} class="loading loading-spinner loading-xs"></span>
      <.icon :if={@status == :saved} name="check" class="size-4 text-success" />
      <span :if={@status == :saving} class="text-base-content/70">{gettext("Saving...")}</span>
      <span :if={@status == :saved} class="text-success">{gettext("Saved")}</span>
    </div>
    """
  end

  attr :type, :string, required: true

  defp node_type_icon(assigns) do
    icon =
      case assigns.type do
        "dialogue" -> "message-square"
        "hub" -> "git-merge"
        "condition" -> "git-branch"
        "instruction" -> "zap"
        "jump" -> "arrow-right"
        _ -> "circle"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <.icon name={@icon} class="size-4" />
    """
  end

  defp node_type_label(type) do
    case type do
      "dialogue" -> gettext("Dialogue")
      "hub" -> gettext("Hub")
      "condition" -> gettext("Condition")
      "instruction" -> gettext("Instruction")
      "jump" -> gettext("Jump")
      _ -> type
    end
  end

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false

  defp node_properties_form(assigns) do
    ~H"""
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      <%= case @node.type do %>
        <% "dialogue" -> %>
          <.input
            field={@form[:speaker]}
            type="text"
            label={gettext("Speaker")}
            placeholder={gettext("Character name")}
            disabled={!@can_edit}
          />
          <.input
            field={@form[:text]}
            type="textarea"
            label={gettext("Text")}
            placeholder={gettext("What the character says...")}
            disabled={!@can_edit}
          />
        <% "hub" -> %>
          <.input
            field={@form[:label]}
            type="text"
            label={gettext("Label")}
            placeholder={gettext("Hub name")}
            disabled={!@can_edit}
          />
        <% "condition" -> %>
          <.input
            field={@form[:expression]}
            type="text"
            label={gettext("Condition")}
            placeholder={gettext("e.g., score > 10")}
            disabled={!@can_edit}
          />
        <% "instruction" -> %>
          <.input
            field={@form[:action]}
            type="text"
            label={gettext("Action")}
            placeholder={gettext("e.g., set_variable")}
            disabled={!@can_edit}
          />
          <.input
            field={@form[:parameters]}
            type="text"
            label={gettext("Parameters")}
            placeholder={gettext("e.g., health = 100")}
            disabled={!@can_edit}
          />
        <% "jump" -> %>
          <.input
            field={@form[:target_flow]}
            type="text"
            label={gettext("Target Flow")}
            placeholder={gettext("Flow name or ID")}
            disabled={!@can_edit}
          />
          <.input
            field={@form[:target_node]}
            type="text"
            label={gettext("Target Node")}
            placeholder={gettext("Node ID (optional)")}
            disabled={!@can_edit}
          />
        <% _ -> %>
          <p class="text-sm text-base-content/60">
            {gettext("No properties for this node type.")}
          </p>
      <% end %>
    </.form>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => flow_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        case Flows.get_flow(project.id, flow_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Flow not found."))
             |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/flows")}

          flow ->
            project = Repo.preload(project, :workspace)
            can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)
            flow_data = Flows.serialize_for_canvas(flow)

            socket =
              socket
              |> assign(:project, project)
              |> assign(:workspace, project.workspace)
              |> assign(:membership, membership)
              |> assign(:flow, flow)
              |> assign(:flow_data, flow_data)
              |> assign(:can_edit, can_edit)
              |> assign(:node_types, @node_types)
              |> assign(:selected_node, nil)
              |> assign(:node_form, nil)
              |> assign(:save_status, :idle)

            {:ok, socket}
        end

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
  def handle_event("add_node", %{"type" => type}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{
          type: type,
          position_x: 100.0 + :rand.uniform(200),
          position_y: 100.0 + :rand.uniform(200),
          data: default_node_data(type)
        }

        case Flows.create_node(socket.assigns.flow, attrs) do
          {:ok, node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)

            node_data = %{
              id: node.id,
              type: node.type,
              position: %{x: node.position_x, y: node.position_y},
              data: node.data
            }

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> push_event("node_added", node_data)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create node."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("node_selected", %{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    form = node_data_to_form(node)

    {:noreply,
     socket
     |> assign(:selected_node, node)
     |> assign(:node_form, form)}
  end

  def handle_event("deselect_node", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)}
  end

  def handle_event("node_moved", %{"id" => node_id, "position_x" => x, "position_y" => y}, socket) do
    node = Flows.get_node_by_id!(node_id)

    case Flows.update_node_position(node, %{position_x: x, position_y: y}) do
      {:ok, _} ->
        schedule_save_status_reset()
        {:noreply, assign(socket, :save_status, :saved)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_node_data", %{"node" => node_params}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = socket.assigns.selected_node

        case Flows.update_node_data(node, node_params) do
          {:ok, updated_node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_node, updated_node)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_node", %{"id" => node_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = Flows.get_node!(socket.assigns.flow.id, node_id)

        case Flows.delete_node(node) do
          {:ok, _} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_node, nil)
             |> assign(:node_form, nil)
             |> push_event("node_removed", %{id: node_id})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete node."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "connection_created",
        %{
          "source_node_id" => source_id,
          "source_pin" => source_pin,
          "target_node_id" => target_id,
          "target_pin" => target_pin
        },
        socket
      ) do
    attrs = %{
      source_node_id: source_id,
      target_node_id: target_id,
      source_pin: source_pin,
      target_pin: target_pin
    }

    case Flows.create_connection_with_attrs(socket.assigns.flow, attrs) do
      {:ok, conn} ->
        flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
        flow_data = Flows.serialize_for_canvas(flow)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, flow)
         |> assign(:flow_data, flow_data)
         |> assign(:save_status, :saved)
         |> push_event("connection_added", %{
           id: conn.id,
           source_node_id: source_id,
           source_pin: source_pin,
           target_node_id: target_id,
           target_pin: target_pin
         })}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create connection."))}
    end
  end

  def handle_event(
        "connection_deleted",
        %{"source_node_id" => source_id, "target_node_id" => target_id},
        socket
      ) do
    Flows.delete_connection_by_nodes(socket.assigns.flow.id, source_id, target_id)

    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)
    schedule_save_status_reset()

    {:noreply,
     socket
     |> assign(:flow, flow)
     |> assign(:flow_data, flow_data)
     |> assign(:save_status, :saved)}
  end

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 2000)
  end

  defp default_node_data(type) do
    case type do
      "dialogue" -> %{"speaker" => "", "text" => ""}
      "hub" -> %{"label" => ""}
      "condition" -> %{"expression" => ""}
      "instruction" -> %{"action" => "", "parameters" => ""}
      "jump" -> %{"target_flow" => "", "target_node" => ""}
      _ -> %{}
    end
  end

  defp node_data_to_form(node) do
    data = extract_node_form_data(node.type, node.data)
    to_form(%{"node" => data}, as: :node)
  end

  defp extract_node_form_data("dialogue", data) do
    %{"speaker" => data["speaker"] || "", "text" => data["text"] || ""}
  end

  defp extract_node_form_data("hub", data) do
    %{"label" => data["label"] || ""}
  end

  defp extract_node_form_data("condition", data) do
    %{"expression" => data["expression"] || ""}
  end

  defp extract_node_form_data("instruction", data) do
    %{"action" => data["action"] || "", "parameters" => data["parameters"] || ""}
  end

  defp extract_node_form_data("jump", data) do
    %{"target_flow" => data["target_flow"] || "", "target_node" => data["target_node"] || ""}
  end

  defp extract_node_form_data(_type, _data), do: %{}
end
