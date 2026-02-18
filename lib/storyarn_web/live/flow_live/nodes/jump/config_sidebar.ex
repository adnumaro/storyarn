defmodule StoryarnWeb.FlowLive.Nodes.Jump.ConfigSidebar do
  @moduledoc """
  Sidebar panel for jump nodes.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :project, :map, required: true
  attr :current_user, :map, required: true
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []

  def config_sidebar(assigns) do
    hub_options =
      [{"", dgettext("flows", "Select target hub...")}] ++
        Enum.map(assigns.flow_hubs, fn hub ->
          display =
            if hub.label && hub.label != "" do
              "#{hub.label} (#{hub.hub_id})"
            else
              hub.hub_id
            end

          {display, hub.hub_id}
        end)

    assigns = assign(assigns, :hub_options, hub_options)

    ~H"""
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      <.input
        field={@form[:target_hub_id]}
        type="select"
        label={dgettext("flows", "Target Hub")}
        options={@hub_options}
        disabled={!@can_edit}
      />
      <p class="text-xs text-base-content/60 mt-1 mb-4">
        {dgettext("flows", "Select a Hub node to jump to within this flow.")}
      </p>
      <button
        :if={@form[:target_hub_id].value && @form[:target_hub_id].value != ""}
        type="button"
        class="btn btn-ghost btn-sm w-full"
        phx-click="navigate_to_hub"
        phx-value-id={@node.id}
      >
        <.icon name="search" class="size-4 mr-2" />
        {dgettext("flows", "Locate target Hub")}
      </button>
      <%= if length(@hub_options) <= 1 do %>
        <div class="alert alert-warning text-sm">
          <.icon name="alert-triangle" class="size-4" />
          <span>{dgettext("flows", "No Hub nodes in this flow. Create a Hub first.")}</span>
        </div>
      <% end %>
    </.form>
    """
  end

  def wrap_in_form?, do: false
end
