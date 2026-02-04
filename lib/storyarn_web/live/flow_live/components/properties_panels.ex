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
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []

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
          flow_hubs={@flow_hubs}
          audio_assets={@audio_assets}
        />
      </div>

      <div class="p-4 border-t border-base-300 space-y-2">
        <button
          :if={@node.type == "dialogue"}
          type="button"
          class="btn btn-primary btn-sm w-full"
          phx-click="open_screenplay"
        >
          <.icon name="maximize-2" class="size-4 mr-2" />
          {gettext("Open Screenplay")}
        </button>
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
          :if={@can_edit && @node.type != "entry"}
          type="button"
          class="btn btn-error btn-outline btn-sm w-full"
          phx-click="delete_node"
          phx-value-id={@node.id}
          data-confirm={gettext("Are you sure you want to delete this node?")}
        >
          <.icon name="trash-2" class="size-4 mr-2" />
          {gettext("Delete Node")}
        </button>
        <p :if={@node.type == "entry"} class="text-xs text-base-content/60 text-center">
          {gettext("Entry nodes cannot be deleted.")}
        </p>
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
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []

  def node_properties_form(assigns) do
    speaker_options =
      [{"", gettext("Select speaker...")}] ++
        Enum.map(assigns.leaf_pages, fn page -> {page.name, page.id} end)

    # Build hub options for Jump node, excluding the current node if it's a hub
    hub_options =
      [{"", gettext("Select target hub...")}] ++
        Enum.map(assigns.flow_hubs, fn hub -> {hub.hub_id, hub.hub_id} end)

    # Build audio asset options for dialogue nodes
    audio_options =
      [{"", gettext("No audio")}] ++
        Enum.map(assigns.audio_assets, fn asset -> {asset.filename, asset.id} end)

    # Find selected audio asset for preview
    selected_audio =
      if assigns.form[:audio_asset_id] && assigns.form[:audio_asset_id].value do
        Enum.find(assigns.audio_assets, fn a ->
          to_string(a.id) == to_string(assigns.form[:audio_asset_id].value)
        end)
      end

    assigns =
      assigns
      |> assign(:speaker_options, speaker_options)
      |> assign(:hub_options, hub_options)
      |> assign(:audio_options, audio_options)
      |> assign(:selected_audio, selected_audio)

    ~H"""
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      <%= case @node.type do %>
        <% "entry" -> %>
          <div class="text-center py-4">
            <.icon name="play" class="size-8 text-success mx-auto mb-2" />
            <p class="text-sm text-base-content/60">
              {gettext("This is the entry point of the flow.")}
            </p>
            <p class="text-xs text-base-content/50 mt-2">
              {gettext("Connect this node to the first node in your flow.")}
            </p>
          </div>
        <% "exit" -> %>
          <.input
            field={@form[:label]}
            type="text"
            label={gettext("Label")}
            placeholder={gettext("e.g., Victory, Defeat")}
            disabled={!@can_edit}
          />
          <p class="text-xs text-base-content/60 mt-2">
            {gettext("Use labels to identify different endings.")}
          </p>
        <% "dialogue" -> %>
          <.input
            field={@form[:speaker_page_id]}
            type="select"
            label={gettext("Speaker")}
            options={@speaker_options}
            disabled={!@can_edit}
          />
          <.input
            field={@form[:stage_directions]}
            type="textarea"
            label={gettext("Stage Directions")}
            placeholder={gettext("(whispering)")}
            disabled={!@can_edit}
            rows={2}
            class="italic font-mono text-sm"
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
          <div class="collapse collapse-arrow bg-base-200 mt-4">
            <input type="checkbox" />
            <div class="collapse-title text-sm font-medium">
              {gettext("Menu Text")}
            </div>
            <div class="collapse-content">
              <.input
                field={@form[:menu_text]}
                type="text"
                placeholder={gettext("Short text shown in response menus")}
                disabled={!@can_edit}
              />
              <p class="text-xs text-base-content/60 mt-1">
                {gettext("Optional shorter text to display in dialogue choice menus.")}
              </p>
            </div>
          </div>
          <div class="collapse collapse-arrow bg-base-200 mt-2">
            <input type="checkbox" checked={@selected_audio != nil} />
            <div class="collapse-title text-sm font-medium flex items-center gap-2">
              <.icon name="volume-2" class="size-4" />
              {gettext("Audio")}
              <span :if={@selected_audio} class="badge badge-primary badge-xs">1</span>
            </div>
            <div class="collapse-content">
              <.input
                field={@form[:audio_asset_id]}
                type="select"
                options={@audio_options}
                disabled={!@can_edit}
              />
              <div :if={@selected_audio} class="mt-3 p-3 bg-base-100 rounded-lg border border-base-300">
                <p class="text-xs text-base-content/60 mb-2 truncate" title={@selected_audio.filename}>
                  {gettext("Preview:")} {@selected_audio.filename}
                </p>
                <audio controls class="w-full h-8">
                  <source src={@selected_audio.url} type={@selected_audio.content_type} />
                  {gettext("Your browser does not support audio playback.")}
                </audio>
              </div>
              <p :if={!@selected_audio} class="text-xs text-base-content/60 mt-2">
                {gettext("Attach voice-over or ambient audio to this dialogue.")}
              </p>
            </div>
          </div>
        <% "hub" -> %>
          <.input
            field={@form[:hub_id]}
            type="text"
            label={gettext("Hub ID")}
            placeholder={gettext("e.g., merchant_done")}
            disabled={!@can_edit}
          />
          <p class="text-xs text-base-content/60 mt-1 mb-4">
            {gettext("Unique identifier for Jump nodes to target this Hub.")}
          </p>
          <.input
            field={@form[:color]}
            type="select"
            label={gettext("Color")}
            options={hub_color_options()}
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
            field={@form[:target_hub_id]}
            type="select"
            label={gettext("Target Hub")}
            options={@hub_options}
            disabled={!@can_edit}
          />
          <p class="text-xs text-base-content/60 mt-1 mb-4">
            {gettext("Select a Hub node to jump to within this flow.")}
          </p>
          <%= if @hub_options == [{"", gettext("Select target hub...")}] do %>
            <div class="alert alert-warning text-sm">
              <.icon name="alert-triangle" class="size-4" />
              <span>{gettext("No Hub nodes in this flow. Create a Hub first.")}</span>
            </div>
          <% end %>
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

  # Hub color options for the color picker
  defp hub_color_options do
    [
      {"purple", gettext("Purple")},
      {"blue", gettext("Blue")},
      {"green", gettext("Green")},
      {"yellow", gettext("Yellow")},
      {"red", gettext("Red")},
      {"pink", gettext("Pink")},
      {"orange", gettext("Orange")},
      {"cyan", gettext("Cyan")}
    ]
  end
end
