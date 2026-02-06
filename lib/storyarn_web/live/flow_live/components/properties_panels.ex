defmodule StoryarnWeb.FlowLive.Components.PropertiesPanels do
  @moduledoc """
  Properties panel components for the flow editor.
  Dispatches to type-specific panel components.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers

  alias StoryarnWeb.FlowLive.Components.Panels.ConditionPanel
  alias StoryarnWeb.FlowLive.Components.Panels.DialoguePanel
  alias StoryarnWeb.FlowLive.Components.Panels.SimplePanels

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :leaf_pages, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []

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
          panel_sections={@panel_sections}
          project_variables={@project_variables}
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

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :leaf_pages, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []

  def node_properties_form(assigns) do
    speaker_options =
      [{"", gettext("Select speaker...")}] ++
        Enum.map(assigns.leaf_pages, fn page -> {page.name, page.id} end)

    hub_options =
      [{"", gettext("Select target hub...")}] ++
        Enum.map(assigns.flow_hubs, fn hub ->
          display =
            if hub.label && hub.label != "" do
              "#{hub.label} (#{hub.hub_id})"
            else
              hub.hub_id
            end

          {display, hub.hub_id}
        end)

    audio_options =
      [{"", gettext("No audio")}] ++
        Enum.map(assigns.audio_assets, fn asset -> {asset.filename, asset.id} end)

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
    <%= if @node.type == "condition" do %>
      <ConditionPanel.condition_properties
        form={@form}
        node={@node}
        can_edit={@can_edit}
        project_variables={@project_variables}
      />
    <% else %>
      <.form for={@form} phx-change="update_node_data" phx-debounce="500">
        <%= case @node.type do %>
          <% "dialogue" -> %>
            <DialoguePanel.dialogue_properties
              form={@form}
              node={@node}
              can_edit={@can_edit}
              speaker_options={@speaker_options}
              audio_options={@audio_options}
              selected_audio={@selected_audio}
              panel_sections={@panel_sections}
              project_variables={@project_variables}
            />
          <% _ -> %>
            <SimplePanels.simple_properties
              node={@node}
              form={@form}
              can_edit={@can_edit}
              hub_options={@hub_options}
            />
        <% end %>
      </.form>
    <% end %>
    """
  end
end
