defmodule StoryarnWeb.SceneLive.Components.CollectionItemsEditor do
  @moduledoc """
  Editor component for collection zone items.

  Renders a list of collectible items, each with sheet picker, label,
  condition builder, and instruction builder.
  """

  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Shared.MapUtils

  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.ExpressionEditor

  attr :zone, :map, required: true
  attr :action_data, :map, required: true
  attr :can_edit, :boolean, default: true
  attr :project_id, :integer, required: true
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  def collection_items_editor(assigns) do
    items = assigns.action_data["items"] || []
    collect_all = assigns.action_data["collect_all_enabled"] != false
    empty_message = assigns.action_data["empty_message"] || ""

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:collect_all, collect_all)
      |> assign(:empty_message, empty_message)

    ~H"""
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <label class="text-xs font-medium text-base-content/60 flex items-center gap-1">
          <.icon name="package-open" class="size-3" />
          {dgettext("scenes", "Collection Items")}
        </label>
        <span class="text-xs text-base-content/40">
          {dngettext("scenes", "%{count} item", "%{count} items", length(@items),
            count: length(@items)
          )}
        </span>
      </div>

      <%!-- Collect All toggle --%>
      <div class="flex items-center justify-between">
        <label class="text-xs text-base-content/60">
          {dgettext("scenes", "Collect All button")}
        </label>
        <input
          type="checkbox"
          class="toggle toggle-xs toggle-primary"
          checked={@collect_all}
          phx-click={
            Phoenix.LiveView.JS.push("update_collection_settings",
              value: %{
                "zone-id" => @zone.id,
                "field" => "collect_all_enabled",
                "value" => to_string(!@collect_all)
              }
            )
          }
          disabled={!@can_edit}
        />
      </div>

      <%!-- Empty message --%>
      <div>
        <label class="block text-xs text-base-content/60 mb-1">
          {dgettext("scenes", "Empty message")}
        </label>
        <input
          type="text"
          value={@empty_message}
          phx-blur="update_collection_settings"
          phx-value-zone-id={@zone.id}
          phx-value-field="empty_message"
          placeholder={dgettext("scenes", "Nothing here...")}
          class="input input-xs input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Items list --%>
      <div class="space-y-2">
        <.collection_item_card
          :for={{item, idx} <- Enum.with_index(@items)}
          item={item}
          idx={idx}
          zone_id={@zone.id}
          can_edit={@can_edit}
          project_id={@project_id}
          project_variables={@project_variables}
          panel_sections={@panel_sections}
        />
      </div>

      <%!-- Add item button --%>
      <button
        :if={@can_edit}
        type="button"
        phx-click="add_collection_item"
        phx-value-zone-id={@zone.id}
        class="btn btn-ghost btn-xs w-full gap-1"
      >
        <.icon name="plus" class="size-3" />
        {dgettext("scenes", "Add item")}
      </button>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :idx, :integer, required: true
  attr :zone_id, :integer, required: true
  attr :can_edit, :boolean, default: true
  attr :project_id, :integer, required: true
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  defp collection_item_card(assigns) do
    item_id = assigns.item["id"]
    sheet_id = assigns.item["sheet_id"]
    parsed_sheet_id = if sheet_id, do: MapUtils.parse_int(sheet_id), else: nil

    assigns =
      assigns
      |> assign(:item_id, item_id)
      |> assign(:parsed_sheet_id, parsed_sheet_id)

    ~H"""
    <div class="border border-base-300 rounded-lg p-2 space-y-2 bg-base-200/30">
      <div class="flex items-center justify-between">
        <span class="text-xs font-semibold text-base-content/60">
          #{@idx + 1}
        </span>
        <button
          :if={@can_edit}
          type="button"
          phx-click="remove_collection_item"
          phx-value-zone-id={@zone_id}
          phx-value-item-id={@item_id}
          class="btn btn-ghost btn-xs btn-square text-error/60 hover:text-error"
        >
          <.icon name="trash-2" class="size-3" />
        </button>
      </div>

      <%!-- Sheet picker --%>
      <.live_component
        module={StoryarnWeb.Components.EntitySelect}
        id={"collection-item-sheet-#{@zone_id}-#{@item_id}"}
        project_id={@project_id}
        entity_type={:sheet}
        selected_id={@parsed_sheet_id}
        label={dgettext("scenes", "Sheet")}
        placeholder={dgettext("scenes", "Select sheet...")}
        disabled={!@can_edit}
      />

      <%!-- Label --%>
      <div>
        <label class="block text-xs text-base-content/50 mb-0.5">
          {dgettext("scenes", "Label")}
        </label>
        <input
          type="text"
          value={@item["label"] || ""}
          phx-blur="update_collection_item"
          phx-value-zone-id={@zone_id}
          phx-value-item-id={@item_id}
          phx-value-field="label"
          placeholder={dgettext("scenes", "Item name...")}
          class="input input-xs input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Condition --%>
      <div>
        <label class="block text-xs text-base-content/50 mb-0.5">
          {dgettext("scenes", "Condition")}
        </label>
        <.condition_builder
          id={"collection-item-condition-#{@item_id}-#{@can_edit}"}
          condition={@item["condition"]}
          variables={@project_variables}
          can_edit={@can_edit}
          event_name="update_collection_item_condition"
          context={%{"zone-id" => @zone_id, "item-id" => @item_id}}
        />
      </div>

      <%!-- Instruction --%>
      <div>
        <label class="block text-xs text-base-content/50 mb-0.5">
          {dgettext("scenes", "Instruction")}
        </label>
        <.expression_editor
          id={"collection-item-instruction-#{@item_id}"}
          mode="instruction"
          assignments={@item["instruction"]["assignments"] || []}
          variables={@project_variables}
          can_edit={@can_edit}
          context={%{"zone-id" => @zone_id, "item-id" => @item_id}}
          event_name="update_collection_item_instruction"
          active_tab={
            Map.get(
              @panel_sections,
              "tab_collection-item-instruction-#{@item_id}",
              "builder"
            )
          }
        />
      </div>
    </div>
    """
  end
end
