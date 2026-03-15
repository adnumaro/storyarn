defmodule StoryarnWeb.Components.BlockComponents.ReferenceBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [block_label: 1, icon: 1]

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :reference_target, :map, default: nil
  attr :target, :any, default: nil

  def reference_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    target_type = get_in(assigns.block.value, ["target_type"])
    target_id = get_in(assigns.block.value, ["target_id"])
    is_constant = assigns.block.is_constant || false

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:target_type, target_type)
      |> assign(:target_id, target_id)
      |> assign(:is_constant, is_constant)
      |> assign(:has_reference, target_type != nil && target_id != nil)

    ~H"""
    <div>
      <.block_label
        label={@label}
        is_constant={@is_constant}
        block_type={@block.type}
        block_id={@block.id}
        can_edit={@can_edit}
        target={@target}
      />

      <%= if @can_edit do %>
        <div
          id={"reference-select-#{@block.id}"}
          phx-hook="ReferenceSelect"
          data-block-id={@block.id}
          data-phx-target={@target}
          data-idle-text={dgettext("sheets", "Type to search...")}
          data-no-results-text={dgettext("sheets", "No results found")}
          class="w-full"
        >
          <button
            type="button"
            data-role="trigger"
            class="input input-bordered w-full flex items-center justify-between cursor-pointer"
          >
            <%= if @has_reference && @reference_target do %>
              <.reference_display target={@reference_target} />
            <% else %>
              <span class="text-base-content/50">{dgettext("sheets", "Select a reference...")}</span>
            <% end %>
            <.icon name="chevron-down" class="size-4 text-base-content/50" />
          </button>

          <template data-role="popover-template">
            <.reference_search
              block_id={@block.id}
              target_type={@target_type}
              target_id={@target_id}
            />
          </template>
        </div>
      <% else %>
        <%= if @has_reference && @reference_target do %>
          <div class="py-2">
            <.reference_display target={@reference_target} linked={true} />
          </div>
        <% else %>
          <div class="py-2 text-base-content/40">-</div>
        <% end %>
      <% end %>

      <%= if @has_reference && is_nil(@reference_target) do %>
        <div class="text-error text-sm mt-1 flex items-center gap-1">
          <.icon name="alert-triangle" class="size-4" />
          {dgettext("sheets", "Reference not found (deleted?)")}
        </div>
      <% end %>
    </div>
    """
  end

  attr :target, :map, required: true
  attr :linked, :boolean, default: false

  defp reference_display(assigns) do
    ~H"""
    <div class="flex items-center gap-2 min-w-0">
      <span class={[
        "flex-shrink-0 size-6 rounded flex items-center justify-center text-xs",
        @target.type == "sheet" && "bg-primary/20 text-primary",
        @target.type == "flow" && "bg-secondary/20 text-secondary"
      ]}>
        <.icon name={if @target.type == "sheet", do: "file-text", else: "git-branch"} class="size-4" />
      </span>
      <span class="truncate font-medium">{@target.name}</span>
      <span :if={@target.shortcut} class="text-base-content/50 text-sm">
        #{@target.shortcut}
      </span>
    </div>
    """
  end

  attr :block_id, :integer, required: true
  attr :target_type, :string, default: nil
  attr :target_id, :integer, default: nil

  defp reference_search(assigns) do
    ~H"""
    <div class="p-2">
      <input
        type="text"
        class="input input-bordered input-sm w-full"
        data-role="search"
        placeholder={dgettext("sheets", "Search sheets and flows...")}
      />
      <div
        id={"reference-results-#{@block_id}"}
        data-role="list"
        class="mt-2 max-h-48 overflow-y-auto"
      >
        <div data-role="empty" class="text-center text-base-content/50 py-4 text-sm">
          {dgettext("sheets", "Type to search...")}
        </div>
      </div>
      <%= if @target_type && @target_id do %>
        <div class="border-t border-base-300 mt-2 pt-2">
          <button
            type="button"
            data-role="clear"
            class="btn btn-ghost btn-sm btn-block text-error"
          >
            <.icon name="x" class="size-4" />
            {dgettext("sheets", "Clear reference")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
