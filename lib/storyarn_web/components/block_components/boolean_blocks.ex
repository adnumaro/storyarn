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
  attr :is_editing, :boolean, default: false

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
    ~H"""
    <label class="flex items-center gap-2 cursor-pointer py-2">
      <input
        type="checkbox"
        checked={@content == true}
        class="checkbox checkbox-primary"
        phx-click="toggle_boolean_block"
        phx-value-id={@block.id}
        phx-value-current={to_string(@content)}
        phx-value-mode="two_state"
      />
      <span class="text-sm text-base-content/70">
        {if @content == true, do: gettext("Yes"), else: gettext("No")}
      </span>
    </label>
    """
  end

  # Tri-state toggle (segmented control: Yes / Neutral / No)
  defp tri_state_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-1 py-2">
      <button
        type="button"
        class={[
          "btn btn-sm",
          @content == true && "btn-success",
          @content != true && "btn-ghost"
        ]}
        phx-click="set_boolean_block"
        phx-value-id={@block.id}
        phx-value-value="true"
      >
        {gettext("Yes")}
      </button>
      <button
        type="button"
        class={[
          "btn btn-sm",
          @content == nil && "btn-neutral",
          @content != nil && "btn-ghost"
        ]}
        phx-click="set_boolean_block"
        phx-value-id={@block.id}
        phx-value-value="null"
      >
        <span class="px-2">—</span>
      </button>
      <button
        type="button"
        class={[
          "btn btn-sm",
          @content == false && "btn-error",
          @content != false && "btn-ghost"
        ]}
        phx-click="set_boolean_block"
        phx-value-id={@block.id}
        phx-value-value="false"
      >
        {gettext("No")}
      </button>
    </div>
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
