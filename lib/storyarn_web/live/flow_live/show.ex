defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  import StoryarnWeb.Layouts, only: [flash_group: 1]

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Pages
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
            data-pages={Jason.encode!(pages_map(@leaf_pages))}
          >
          </div>
        </div>

        <%!-- Node Properties Panel --%>
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
              leaf_pages={@leaf_pages}
            />
          </div>

          <div class="p-4 border-t border-base-300 space-y-2">
            <button
              :if={@selected_node.type == "dialogue"}
              type="button"
              class="btn btn-ghost btn-sm w-full"
              phx-click="start_preview"
              phx-value-id={@selected_node.id}
            >
              <.icon name="play" class="size-4 mr-2" />
              {gettext("Preview from here")}
            </button>
            <button
              :if={@can_edit}
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

        <%!-- Connection Properties Panel --%>
        <aside
          :if={@selected_connection && !@selected_node}
          class="w-80 bg-base-100 border-l border-base-300 flex flex-col overflow-hidden"
        >
          <div class="p-4 border-b border-base-300 flex items-center justify-between">
            <h2 class="font-medium flex items-center gap-2">
              <.icon name="git-commit-horizontal" class="size-4" />
              {gettext("Connection")}
            </h2>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square"
              phx-click="deselect_connection"
            >
              <.icon name="x" class="size-4" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-4">
            <.form for={@connection_form} phx-change="update_connection_data" phx-debounce="500">
              <.input
                field={@connection_form[:label]}
                type="text"
                label={gettext("Label")}
                placeholder={gettext("Optional label")}
                disabled={!@can_edit}
              />
              <.input
                field={@connection_form[:condition]}
                type="text"
                label={gettext("Condition")}
                placeholder={gettext("e.g., score > 10")}
                disabled={!@can_edit}
              />
            </.form>
          </div>

          <div :if={@can_edit} class="p-4 border-t border-base-300">
            <button
              type="button"
              class="btn btn-error btn-outline btn-sm w-full"
              phx-click="delete_connection"
              phx-value-id={@selected_connection.id}
              data-confirm={gettext("Are you sure you want to delete this connection?")}
            >
              <.icon name="trash-2" class="size-4 mr-2" />
              {gettext("Delete Connection")}
            </button>
          </div>
        </aside>
      </div>

      <.flash_group flash={@flash} />

      <%!-- Preview Modal --%>
      <.live_component
        module={StoryarnWeb.FlowLive.PreviewComponent}
        id="flow-preview"
        show={@preview_show}
        start_node={@preview_node}
        project={@project}
        pages_map={pages_map(@leaf_pages)}
      />
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
  attr :leaf_pages, :list, default: []

  defp node_properties_form(assigns) do
    speaker_options =
      [{"", gettext("Select speaker...")}] ++
        Enum.map(assigns.leaf_pages, fn page -> {page.id, page.name} end)

    assigns = assign(assigns, :speaker_options, speaker_options)

    ~H"""
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      <%= case @node.type do %>
        <% "dialogue" -> %>
          <.input
            field={@form[:speaker_page_id]}
            type="select"
            label={gettext("Speaker")}
            options={@speaker_options}
            disabled={!@can_edit}
          />
          <div class="form-control mt-4">
            <label class="label">
              <span class="label-text">{gettext("Text")}</span>
            </label>
            <div
              id={"dialogue-text-editor-#{@node.id}"}
              phx-hook="TiptapEditor"
              phx-update="ignore"
              data-node-id={@node.id}
              data-content={@form[:text].value || ""}
              data-editable={to_string(@can_edit)}
              class="border border-base-300 rounded-lg bg-base-100 p-2"
            >
            </div>
          </div>

          <%!-- Response Branches --%>
          <div class="form-control mt-4">
            <label class="label">
              <span class="label-text">{gettext("Responses")}</span>
            </label>
            <div class="space-y-2">
              <div
                :for={response <- @form[:responses].value || []}
                class="p-2 bg-base-200 rounded-lg space-y-2"
              >
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    value={response["text"]}
                    phx-blur="update_response_text"
                    phx-value-response-id={response["id"]}
                    phx-value-node-id={@node.id}
                    disabled={!@can_edit}
                    placeholder={gettext("Response text...")}
                    class="input input-sm input-bordered flex-1"
                  />
                  <button
                    :if={@can_edit}
                    type="button"
                    phx-click="remove_response"
                    phx-value-response-id={response["id"]}
                    phx-value-node-id={@node.id}
                    class="btn btn-ghost btn-xs btn-square text-error"
                    title={gettext("Remove response")}
                  >
                    <.icon name="x" class="size-3" />
                  </button>
                </div>
                <div class="flex items-center gap-2">
                  <.icon name="git-branch" class="size-3 text-base-content/50" />
                  <input
                    type="text"
                    value={response["condition"]}
                    phx-blur="update_response_condition"
                    phx-value-response-id={response["id"]}
                    phx-value-node-id={@node.id}
                    disabled={!@can_edit}
                    placeholder={gettext("Condition (optional)")}
                    class="input input-xs input-bordered flex-1 font-mono text-xs"
                  />
                </div>
              </div>
              <button
                :if={@can_edit}
                type="button"
                phx-click="add_response"
                phx-value-node-id={@node.id}
                class="btn btn-ghost btn-sm gap-1 w-full border border-dashed border-base-300"
              >
                <.icon name="plus" class="size-4" />
                {gettext("Add response")}
              </button>
            </div>
            <p :if={(@form[:responses].value || []) == []} class="text-xs text-base-content/60 mt-1">
              {gettext("No responses means a simple dialogue with one output.")}
            </p>
          </div>
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
            leaf_pages = Pages.list_leaf_pages(project.id)

            socket =
              socket
              |> assign(:project, project)
              |> assign(:workspace, project.workspace)
              |> assign(:membership, membership)
              |> assign(:flow, flow)
              |> assign(:flow_data, flow_data)
              |> assign(:can_edit, can_edit)
              |> assign(:node_types, @node_types)
              |> assign(:leaf_pages, leaf_pages)
              |> assign(:selected_node, nil)
              |> assign(:node_form, nil)
              |> assign(:selected_connection, nil)
              |> assign(:connection_form, nil)
              |> assign(:save_status, :idle)
              |> assign(:preview_show, false)
              |> assign(:preview_node, nil)

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

  def handle_event("connection_selected", %{"id" => connection_id}, socket) do
    connection = Flows.get_connection!(socket.assigns.flow.id, connection_id)
    form = connection_data_to_form(connection)

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)
     |> assign(:selected_connection, connection)
     |> assign(:connection_form, form)}
  end

  def handle_event("deselect_connection", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_connection, nil)
     |> assign(:connection_form, nil)
     |> push_event("deselect_connection", %{})}
  end

  def handle_event("update_connection_data", %{"connection" => conn_params}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        connection = socket.assigns.selected_connection

        case Flows.update_connection(connection, conn_params) do
          {:ok, updated_connection} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_connection, updated_connection)
             |> assign(:save_status, :saved)
             |> push_event("connection_updated", %{
               id: updated_connection.id,
               label: updated_connection.label,
               condition: updated_connection.condition
             })}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_connection", %{"id" => connection_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        connection = Flows.get_connection!(socket.assigns.flow.id, connection_id)

        case Flows.delete_connection(connection) do
          {:ok, _} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_connection, nil)
             |> assign(:connection_form, nil)
             |> push_event("connection_removed", %{
               source_node_id: connection.source_node_id,
               target_node_id: connection.target_node_id
             })}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete connection."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
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

  def handle_event("update_node_text", %{"id" => node_id, "content" => content}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = Flows.get_node!(socket.assigns.flow.id, node_id)
        updated_data = Map.put(node.data, "text", content)

        case Flows.update_node_data(node, updated_data) do
          {:ok, updated_node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)
            schedule_save_status_reset()

            # Update selected_node if this is the currently selected node
            socket =
              if socket.assigns.selected_node && socket.assigns.selected_node.id == node.id do
                form = node_data_to_form(updated_node)
                assign(socket, selected_node: updated_node, node_form: form)
              else
                socket
              end

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("add_response", %{"node-id" => node_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = Flows.get_node!(socket.assigns.flow.id, node_id)
        responses = node.data["responses"] || []

        # Generate a unique ID for the new response
        new_id = "r#{length(responses) + 1}_#{:erlang.unique_integer([:positive])}"
        new_response = %{"id" => new_id, "text" => "", "condition" => nil}
        updated_responses = responses ++ [new_response]

        updated_data = Map.put(node.data, "responses", updated_responses)

        case Flows.update_node_data(node, updated_data) do
          {:ok, updated_node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)
            form = node_data_to_form(updated_node)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_node, updated_node)
             |> assign(:node_form, form)
             |> assign(:save_status, :saved)
             |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_response", %{"response-id" => response_id, "node-id" => node_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = Flows.get_node!(socket.assigns.flow.id, node_id)
        responses = node.data["responses"] || []

        updated_responses = Enum.reject(responses, fn r -> r["id"] == response_id end)
        updated_data = Map.put(node.data, "responses", updated_responses)

        case Flows.update_node_data(node, updated_data) do
          {:ok, updated_node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)
            form = node_data_to_form(updated_node)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_node, updated_node)
             |> assign(:node_form, form)
             |> assign(:save_status, :saved)
             |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "update_response_text",
        %{"response-id" => response_id, "node-id" => node_id, "value" => text},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = Flows.get_node!(socket.assigns.flow.id, node_id)
        responses = node.data["responses"] || []

        updated_responses =
          Enum.map(responses, fn r ->
            if r["id"] == response_id, do: Map.put(r, "text", text), else: r
          end)

        updated_data = Map.put(node.data, "responses", updated_responses)

        case Flows.update_node_data(node, updated_data) do
          {:ok, updated_node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)
            form = node_data_to_form(updated_node)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_node, updated_node)
             |> assign(:node_form, form)
             |> assign(:save_status, :saved)
             |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "update_response_condition",
        %{"response-id" => response_id, "node-id" => node_id, "value" => condition},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = Flows.get_node!(socket.assigns.flow.id, node_id)
        responses = node.data["responses"] || []

        updated_responses =
          Enum.map(responses, fn r ->
            if r["id"] == response_id do
              # Store nil if empty string for cleaner data
              Map.put(r, "condition", if(condition == "", do: nil, else: condition))
            else
              r
            end
          end)

        updated_data = Map.put(node.data, "responses", updated_responses)

        case Flows.update_node_data(node, updated_data) do
          {:ok, updated_node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)
            form = node_data_to_form(updated_node)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> assign(:selected_node, updated_node)
             |> assign(:node_form, form)
             |> assign(:save_status, :saved)
             |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

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

  def handle_event("duplicate_node", %{"id" => node_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = Flows.get_node!(socket.assigns.flow.id, node_id)

        attrs = %{
          type: node.type,
          position_x: node.position_x + 50.0,
          position_y: node.position_y + 50.0,
          data: node.data
        }

        case Flows.create_node(socket.assigns.flow, attrs) do
          {:ok, new_node} ->
            flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
            flow_data = Flows.serialize_for_canvas(flow)

            node_data = %{
              id: new_node.id,
              type: new_node.type,
              position: %{x: new_node.position_x, y: new_node.position_y},
              data: new_node.data
            }

            {:noreply,
             socket
             |> assign(:flow, flow)
             |> assign(:flow_data, flow_data)
             |> push_event("node_added", node_data)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not duplicate node."))}
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

  def handle_event("start_preview", %{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)

    {:noreply,
     socket
     |> assign(:preview_show, true)
     |> assign(:preview_node, node)}
  end

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  def handle_info({:close_preview}, socket) do
    {:noreply, assign(socket, preview_show: false, preview_node: nil)}
  end

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 2000)
  end

  defp default_node_data(type) do
    case type do
      "dialogue" -> %{"speaker_page_id" => nil, "text" => "", "responses" => []}
      "hub" -> %{"label" => ""}
      "condition" -> %{"expression" => ""}
      "instruction" -> %{"action" => "", "parameters" => ""}
      "jump" -> %{"target_flow" => "", "target_node" => ""}
      _ -> %{}
    end
  end

  defp node_data_to_form(node) do
    data = extract_node_form_data(node.type, node.data)
    to_form(data, as: :node)
  end

  defp extract_node_form_data("dialogue", data) do
    %{
      "speaker_page_id" => data["speaker_page_id"] || "",
      "text" => data["text"] || "",
      "responses" => data["responses"] || []
    }
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

  defp connection_data_to_form(connection) do
    data = %{
      "label" => connection.label || "",
      "condition" => connection.condition || ""
    }

    to_form(data, as: :connection)
  end

  defp pages_map(leaf_pages) do
    Map.new(leaf_pages, fn page -> {to_string(page.id), %{id: page.id, name: page.name}} end)
  end
end
