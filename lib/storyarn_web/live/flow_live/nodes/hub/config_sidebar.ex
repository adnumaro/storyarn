defmodule StoryarnWeb.FlowLive.Nodes.Hub.ConfigSidebar do
  @moduledoc """
  Sidebar panel for hub nodes.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Flows.HubColors

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []

  def config_sidebar(assigns) do
    ~H"""
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      <.input
        field={@form[:label]}
        type="text"
        label={gettext("Label")}
        placeholder={gettext("e.g., Merchant conversation")}
        disabled={!@can_edit}
      />
      <.input
        field={@form[:hub_id]}
        type="text"
        label={gettext("Hub ID") <> " *"}
        placeholder={gettext("e.g., merchant_done")}
        disabled={!@can_edit}
      />
      <p class="text-xs text-base-content/60 mt-1 mb-4">
        {gettext("Required. Unique identifier for Jump nodes to target this Hub.")}
      </p>
      <.input
        field={@form[:color]}
        type="select"
        label={gettext("Color")}
        options={hub_color_options()}
        disabled={!@can_edit}
      />
      <div class="mt-6">
        <h3 class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-2">
          {gettext("Referencing Jumps")}
          <span class="text-base-content/40 ml-1">({length(@referencing_jumps)})</span>
        </h3>
        <%= if @referencing_jumps == [] do %>
          <p class="text-xs text-base-content/40 italic">
            {gettext("No Jump nodes target this Hub yet.")}
          </p>
        <% else %>
          <div class="space-y-1">
            <button
              :for={jump <- @referencing_jumps}
              type="button"
              class="btn btn-ghost btn-xs w-full justify-start gap-2 font-normal"
              phx-click="navigate_to_node"
              phx-value-id={jump.id}
            >
              <.icon name="log-out" class="size-3 opacity-60" />
              <span class="truncate">Jump #{jump.id}</span>
              <.icon name="crosshair" class="size-3 opacity-40 ml-auto" />
            </button>
          </div>
          <button
            type="button"
            class="btn btn-ghost btn-xs w-full mt-2"
            phx-click="navigate_to_jumps"
            phx-value-id={@node.id}
          >
            <.icon name="search" class="size-3 mr-1" />
            {gettext("Locate all")}
          </button>
        <% end %>
      </div>
    </.form>
    """
  end

  def wrap_in_form?, do: false

  defp hub_color_options do
    color_labels = %{
      "purple" => gettext("Purple"),
      "blue" => gettext("Blue"),
      "green" => gettext("Green"),
      "yellow" => gettext("Yellow"),
      "red" => gettext("Red"),
      "pink" => gettext("Pink"),
      "orange" => gettext("Orange"),
      "cyan" => gettext("Cyan")
    }

    Enum.map(HubColors.names(), fn name ->
      {Map.get(color_labels, name, name), name}
    end)
  end
end
