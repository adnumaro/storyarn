defmodule StoryarnWeb.Components.BlockComponents.BooleanBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [block_label: 1]

  @doc """
  Renders a boolean block with support for two-state (true/false) or tri-state (true/null/false).

  ## Modes

  - `two_state` - Simple checkbox toggle (true/false)
  - `tri_state` - Three-way toggle (true/neutral/false)

  ## Examples

      <.boolean_block block={@block} can_edit={true} />
  """
  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def boolean_block(assigns) do
    config = assigns.block.config || %{}
    label = config["label"] || ""
    mode = config["mode"] || "two_state"
    content = get_in(assigns.block.value, ["content"])
    is_constant = assigns.block.is_constant || false

    # Custom labels with defaults
    true_label = non_empty_or_default(config["true_label"], gettext("Yes"))
    false_label = non_empty_or_default(config["false_label"], gettext("No"))
    neutral_label = non_empty_or_default(config["neutral_label"], gettext("Neutral"))

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:mode, mode)
      |> assign(:content, content)
      |> assign(:true_label, true_label)
      |> assign(:false_label, false_label)
      |> assign(:neutral_label, neutral_label)
      |> assign(:is_constant, is_constant)

    ~H"""
    <div class="py-1">
      <.block_label label={@label} is_constant={@is_constant} />

      <%= if @can_edit do %>
        <%= if @mode == "two_state" do %>
          <.two_state_toggle
            block={@block}
            content={@content}
            true_label={@true_label}
            false_label={@false_label}
          />
        <% else %>
          <.tri_state_toggle
            block={@block}
            content={@content}
            true_label={@true_label}
            false_label={@false_label}
            neutral_label={@neutral_label}
          />
        <% end %>
      <% else %>
        <.boolean_display
          content={@content}
          mode={@mode}
          true_label={@true_label}
          false_label={@false_label}
          neutral_label={@neutral_label}
        />
      <% end %>
    </div>
    """
  end

  defp non_empty_or_default(nil, default), do: default
  defp non_empty_or_default("", default), do: default
  defp non_empty_or_default(value, _default), do: value

  # Two-state toggle (simple checkbox)
  defp two_state_toggle(assigns) do
    state_string = if assigns.content == true, do: "true", else: "false"
    label_text = if assigns.content == true, do: assigns.true_label, else: assigns.false_label

    assigns =
      assigns
      |> assign(:state_string, state_string)
      |> assign(:label_text, label_text)

    ~H"""
    <label class="flex items-center gap-2 cursor-pointer py-2">
      <input
        type="checkbox"
        checked={@content == true}
        class="checkbox checkbox-primary"
        phx-hook="TwoStateCheckbox"
        id={"two-state-#{@block.id}"}
        data-block-id={@block.id}
        data-state={@state_string}
      />
      <span class="text-sm text-base-content/70">
        {@label_text}
      </span>
    </label>
    """
  end

  # Tri-state toggle (checkbox with indeterminate state)
  # States cycle: true → false → null → true
  defp tri_state_toggle(assigns) do
    content = assigns.content

    # Label text based on current state using custom labels
    label_text =
      cond do
        content == true -> assigns.true_label
        content == false -> assigns.false_label
        true -> assigns.neutral_label
      end

    # Determine if indeterminate (nil or any non-boolean value)
    is_indeterminate = content != true and content != false

    # State string for the hook
    state_string =
      cond do
        content == true -> "true"
        content == false -> "false"
        true -> "null"
      end

    assigns =
      assigns
      |> assign(:label_text, label_text)
      |> assign(:is_indeterminate, is_indeterminate)
      |> assign(:state_string, state_string)

    ~H"""
    <label class="flex items-center gap-2 cursor-pointer py-2">
      <input
        type="checkbox"
        checked={@content == true}
        class="checkbox checkbox-primary"
        phx-hook="TriStateCheckbox"
        id={"tri-state-#{@block.id}"}
        data-indeterminate={to_string(@is_indeterminate)}
        data-block-id={@block.id}
        data-state={@state_string}
      />
      <span class="text-sm text-base-content/70">
        {@label_text}
      </span>
    </label>
    """
  end

  # Read-only display
  defp boolean_display(assigns) do
    ~H"""
    <div class="py-2 min-h-10 flex items-center gap-2">
      <%= case @content do %>
        <% true -> %>
          <span class="badge badge-success gap-1">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="size-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            {@true_label}
          </span>
        <% false -> %>
          <span class="badge badge-error gap-1">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="size-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
            {@false_label}
          </span>
        <% nil -> %>
          <%= if @mode == "tri_state" do %>
            <span class="badge badge-neutral">{@neutral_label}</span>
          <% else %>
            <span class="text-base-content/40">—</span>
          <% end %>
        <% _ -> %>
          <span class="text-base-content/40">—</span>
      <% end %>
    </div>
    """
  end
end
