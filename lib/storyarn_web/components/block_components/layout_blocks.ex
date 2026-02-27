defmodule StoryarnWeb.Components.BlockComponents.LayoutBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [block_label: 1]

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :target, :any, default: nil

  def date_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    content = get_in(assigns.block.value, ["content"])
    formatted = format_date(content)
    is_constant = assigns.block.is_constant || false

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:content, content)
      |> assign(:formatted, formatted)
      |> assign(:is_constant, is_constant)

    ~H"""
    <div class="py-1">
      <.block_label
        label={@label}
        is_constant={@is_constant}
        block_id={@block.id}
        can_edit={@can_edit}
        target={@target}
      />
      <input
        :if={@can_edit}
        type="date"
        value={@content}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
        phx-target={@target}
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
