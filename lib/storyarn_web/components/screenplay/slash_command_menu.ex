defmodule StoryarnWeb.Components.Screenplay.SlashCommandMenu do
  @moduledoc """
  Floating command palette for the screenplay editor.

  Displayed when the user types `/` in an empty element. Items are grouped
  into Screenplay, Interactive, and Utility categories.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @commands [
    # {type, icon, label_key, description_key, group}
    {"scene_heading", "clapperboard", "Scene Heading", "INT./EXT. Location - Time", :screenplay},
    {"action", "align-left", "Action", "Narrative description", :screenplay},
    {"character", "user", "Character", "Character name (ALL CAPS)", :screenplay},
    {"dialogue", "message-square", "Dialogue", "Spoken text", :screenplay},
    {"parenthetical", "parentheses", "Parenthetical", "(acting direction)", :screenplay},
    {"transition", "arrow-right", "Transition", "CUT TO:, FADE IN:", :screenplay},
    {"conditional", "git-branch", "Condition", "Branch based on variable", :interactive},
    {"instruction", "zap", "Instruction", "Modify a variable", :interactive},
    {"response", "list", "Responses", "Player choices", :interactive},
    {"note", "sticky-note", "Note", "Writer's note (not exported)", :utility},
    {"section", "heading", "Section", "Outline header", :utility},
    {"page_break", "scissors", "Page Break", "Force page break", :utility}
  ]

  attr :element_id, :integer, required: true

  def slash_command_menu(assigns) do
    assigns = assign(assigns, :commands, @commands)

    ~H"""
    <div
      id="slash-command-menu"
      class="slash-menu"
      phx-hook="SlashCommand"
      data-target-id={"sp-el-#{@element_id}"}
      phx-click-away="close_slash_menu"
    >
      <div class="slash-menu-search">
        <input
          type="text"
          id="slash-menu-search-input"
          class="slash-menu-search-input"
          placeholder={gettext("Filter commands...")}
          autocomplete="off"
          phx-update="ignore"
        />
      </div>
      <div class="slash-menu-list" id="slash-menu-list">
        <.slash_group label={gettext("Screenplay")}>
          <.slash_item
            :for={{type, icon, label, desc, :screenplay} <- @commands}
            type={type}
            icon={icon}
            label={label}
            description={desc}
          />
        </.slash_group>
        <.slash_group label={gettext("Interactive")}>
          <.slash_item
            :for={{type, icon, label, desc, :interactive} <- @commands}
            type={type}
            icon={icon}
            label={label}
            description={desc}
          />
        </.slash_group>
        <.slash_group label={gettext("Utility")}>
          <.slash_item
            :for={{type, icon, label, desc, :utility} <- @commands}
            type={type}
            icon={icon}
            label={label}
            description={desc}
          />
        </.slash_group>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp slash_group(assigns) do
    ~H"""
    <div class="slash-menu-group" data-group={@label}>
      <div class="slash-menu-group-label">{@label}</div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :type, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true

  defp slash_item(assigns) do
    ~H"""
    <button
      type="button"
      class="slash-menu-item"
      data-type={@type}
      data-label={@label}
      phx-click="select_slash_command"
      phx-value-type={@type}
    >
      <.icon name={@icon} class="slash-menu-item-icon" />
      <div class="slash-menu-item-text">
        <span class="slash-menu-item-label">{@label}</span>
        <span class="slash-menu-item-desc">{@description}</span>
      </div>
    </button>
    """
  end
end
