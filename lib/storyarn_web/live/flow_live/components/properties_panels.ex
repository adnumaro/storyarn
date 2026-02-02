defmodule StoryarnWeb.FlowLive.Components.PropertiesPanels do
  @moduledoc """
  Properties panel components for the flow editor.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers

  @doc """
  Renders the node properties panel.
  """
  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :leaf_pages, :list, default: []

  def node_properties_panel(assigns) do
    ~H"""
    <aside class="w-80 bg-base-100 border-l border-base-300 flex flex-col overflow-hidden">
      <div class="p-4 border-b border-base-300 flex items-center justify-between">
        <h2 class="font-medium flex items-center gap-2">
          <.node_type_icon type={@node.type} />
          {node_type_label(@node.type)}
        </h2>
        <button type="button" class="btn btn-ghost btn-xs btn-square" phx-click="deselect_node">
          <.icon name="x" class="size-4" />
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-4">
        <.node_properties_form
          node={@node}
          form={@form}
          can_edit={@can_edit}
          leaf_pages={@leaf_pages}
        />
      </div>

      <div class="p-4 border-t border-base-300 space-y-2">
        <button
          :if={@node.type == "dialogue"}
          type="button"
          class="btn btn-ghost btn-sm w-full"
          phx-click="start_preview"
          phx-value-id={@node.id}
        >
          <.icon name="play" class="size-4 mr-2" />
          {gettext("Preview from here")}
        </button>
        <button
          :if={@can_edit}
          type="button"
          class="btn btn-error btn-outline btn-sm w-full"
          phx-click="delete_node"
          phx-value-id={@node.id}
          data-confirm={gettext("Are you sure you want to delete this node?")}
        >
          <.icon name="trash-2" class="size-4 mr-2" />
          {gettext("Delete Node")}
        </button>
      </div>
    </aside>
    """
  end

  @doc """
  Renders the connection properties panel.
  """
  attr :connection, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false

  def connection_properties_panel(assigns) do
    ~H"""
    <aside class="w-80 bg-base-100 border-l border-base-300 flex flex-col overflow-hidden">
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
        <.form for={@form} phx-change="update_connection_data" phx-debounce="500">
          <.input
            field={@form[:label]}
            type="text"
            label={gettext("Label")}
            placeholder={gettext("Optional label")}
            disabled={!@can_edit}
          />
          <.input
            field={@form[:condition]}
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
          phx-value-id={@connection.id}
          data-confirm={gettext("Are you sure you want to delete this connection?")}
        >
          <.icon name="trash-2" class="size-4 mr-2" />
          {gettext("Delete Connection")}
        </button>
      </div>
    </aside>
    """
  end

  @doc """
  Renders the node properties form based on node type.
  """
  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :leaf_pages, :list, default: []

  def node_properties_form(assigns) do
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
          <.dialogue_responses_form form={@form} node={@node} can_edit={@can_edit} />
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

  @doc """
  Renders the dialogue responses form section.
  """
  attr :form, :map, required: true
  attr :node, :map, required: true
  attr :can_edit, :boolean, default: false

  def dialogue_responses_form(assigns) do
    ~H"""
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
    """
  end
end
