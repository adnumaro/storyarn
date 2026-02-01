defmodule StoryarnWeb.Components.BlockComponents.TextBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def text_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || ""
    content = get_in(assigns.block.value, ["content"]) || ""

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
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

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:content, content)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
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

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
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
