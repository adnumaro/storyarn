defmodule StoryarnWeb.Components.BlockComponents.LayoutBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  def divider_block(assigns) do
    ~H"""
    <div class="py-3">
      <hr class="border-base-content/20" />
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def date_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    content = get_in(assigns.block.value, ["content"])
    formatted = format_date(content)

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:content, content)
      |> assign(:formatted, formatted)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <input
        :if={@can_edit}
        type="date"
        value={@content}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div
        :if={!@can_edit}
        class={["py-2 min-h-10", @content in [nil, ""] && "text-base-content/40"]}
      >
        {@formatted}
      </div>
    </div>
    """
  end

  defp format_date(nil), do: "-"
  defp format_date(""), do: "-"

  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end
end
