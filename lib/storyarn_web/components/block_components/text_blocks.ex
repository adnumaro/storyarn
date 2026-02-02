defmodule StoryarnWeb.Components.BlockComponents.TextBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [block_label: 1]

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def text_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || ""
    content = get_in(assigns.block.value, ["content"]) || ""
    is_constant = assigns.block.is_constant || false

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)
      |> assign(:is_constant, is_constant)

    ~H"""
    <div class="py-1">
      <.block_label label={@label} is_constant={@is_constant} />
      <input
        :if={@can_edit}
        type="text"
        value={@content}
        placeholder={@placeholder}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div :if={!@can_edit} class={["py-2 min-h-10", @content == "" && "text-base-content/40"]}>
        {if @content == "", do: "-", else: @content}
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def rich_text_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    content = get_in(assigns.block.value, ["content"]) || ""
    is_constant = assigns.block.is_constant || false

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:content, content)
      |> assign(:is_constant, is_constant)

    ~H"""
    <div class="py-1">
      <.block_label label={@label} is_constant={@is_constant} />
      <div
        id={"tiptap-#{@block.id}"}
        phx-hook="TiptapEditor"
        phx-update="ignore"
        data-content={@content}
        data-editable={to_string(@can_edit)}
        data-block-id={@block.id}
      >
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def number_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || "0"
    content = get_in(assigns.block.value, ["content"])
    is_constant = assigns.block.is_constant || false

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)
      |> assign(:is_constant, is_constant)

    ~H"""
    <div class="py-1">
      <.block_label label={@label} is_constant={@is_constant} />
      <input
        :if={@can_edit}
        type="number"
        value={@content}
        placeholder={@placeholder}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div :if={!@can_edit} class={["py-2 min-h-10", @content == nil && "text-base-content/40"]}>
        {@content || "-"}
      </div>
    </div>
    """
  end
end
