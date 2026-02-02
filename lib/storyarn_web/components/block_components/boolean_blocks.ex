defmodule StoryarnWeb.Components.BlockComponents.BooleanBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

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
    label = get_in(assigns.block.config, ["label"]) || ""
    mode = get_in(assigns.block.config, ["mode"]) || "two_state"
    content = get_in(assigns.block.value, ["content"])

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:mode, mode)
      |> assign(:content, content)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>

      <%= if @can_edit do %>
        <%= if @mode == "two_state" do %>
          <.two_state_toggle block={@block} content={@content} />
        <% else %>
          <.tri_state_toggle block={@block} content={@content} />
        <% end %>
      <% else %>
        <.boolean_display content={@content} mode={@mode} />
      <% end %>
    </div>
    """
  end

  # Two-state toggle (simple checkbox)
  defp two_state_toggle(assigns) do
    state_string = if assigns.content == true, do: "true", else: "false"
    assigns = assign(assigns, :state_string, state_string)

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
        {if @content == true, do: gettext("Yes"), else: gettext("No")}
      </span>
    </label>
    """
  end

  # Tri-state toggle (checkbox with indeterminate state)
  # States cycle: true → false → null → true
  defp tri_state_toggle(assigns) do
    content = assigns.content

    # Label text based on current state
    label_text =
      cond do
        content == true -> gettext("Yes")
        content == false -> gettext("No")
        true -> gettext("Neutral")
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
            {gettext("Yes")}
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
            {gettext("No")}
          </span>
        <% nil -> %>
          <%= if @mode == "tri_state" do %>
            <span class="badge badge-neutral">{gettext("Neutral")}</span>
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
