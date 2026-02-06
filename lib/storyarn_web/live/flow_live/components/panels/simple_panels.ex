defmodule StoryarnWeb.FlowLive.Components.Panels.SimplePanels do
  @moduledoc """
  Properties panel components for simple node types.

  Renders: entry, exit, hub, instruction, jump panels.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Flows.HubColors

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :hub_options, :list, default: []
  attr :referencing_jumps, :list, default: []

  def simple_properties(assigns) do
    ~H"""
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
        <.input
          field={@form[:is_success]}
          type="checkbox"
          label={gettext("Success ending")}
          disabled={!@can_edit}
        />
        <p class="text-xs text-base-content/60 mt-1">
          {gettext("Uncheck for failure/game-over endings.")}
        </p>
        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">{gettext("Technical ID")}</span>
          </label>
          <div class="join w-full">
            <input
              type="text"
              name="technical_id"
              value={@form[:technical_id].value || ""}
              phx-blur="update_node_field"
              phx-value-field="technical_id"
              disabled={!@can_edit}
              placeholder={gettext("e.g., victory_ending_1")}
              class="input input-sm input-bordered join-item flex-1 font-mono text-xs"
            />
            <button
              :if={@can_edit}
              type="button"
              phx-click="generate_technical_id"
              onclick="event.stopPropagation()"
              class="btn btn-sm btn-ghost join-item"
              title={gettext("Generate ID")}
            >
              <.icon name="refresh-cw" class="size-3" />
            </button>
          </div>
          <p class="text-xs text-base-content/60 mt-1">
            {gettext("Unique identifier for export and game integration.")}
          </p>
        </div>
      <% "hub" -> %>
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
        <button
          :if={@form[:target_hub_id].value && @form[:target_hub_id].value != ""}
          type="button"
          class="btn btn-ghost btn-sm w-full"
          phx-click="navigate_to_hub"
          phx-value-id={@node.id}
        >
          <.icon name="search" class="size-4 mr-2" />
          {gettext("Locate target Hub")}
        </button>
        <%= if length(@hub_options) <= 1 do %>
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
    """
  end

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
