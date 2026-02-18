defmodule StoryarnWeb.ScreenplayLive.Components.ScreenplayToolbar do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CoreComponents

  alias Storyarn.Screenplays.Screenplay

  attr :screenplay, :map, required: true
  attr :elements, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :read_mode, :boolean, default: false
  attr :can_edit, :boolean, required: true
  attr :link_status, :atom, required: true
  attr :linked_flow, :any, default: nil

  def screenplay_toolbar(assigns) do
    ~H"""
    <div class="screenplay-toolbar" id="screenplay-toolbar">
      <div class="screenplay-toolbar-left">
        <h1
          :if={@can_edit}
          id="screenplay-title"
          class="screenplay-toolbar-title"
          contenteditable="true"
          phx-hook="EditableTitle"
          phx-update="ignore"
          data-placeholder={dgettext("screenplays", "Untitled")}
          data-name={@screenplay.name}
        >
          {@screenplay.name}
        </h1>
        <h1 :if={!@can_edit} class="screenplay-toolbar-title">
          {@screenplay.name}
        </h1>
      </div>
      <div class="screenplay-toolbar-right">
        <span class="screenplay-toolbar-badge" id="screenplay-element-count">
          {dngettext("screenplays", "%{count} element", "%{count} elements", length(@elements))}
        </span>
        <span
          :if={Screenplay.draft?(@screenplay)}
          class="screenplay-toolbar-badge screenplay-toolbar-draft"
        >
          {dgettext("screenplays", "Draft")}
        </span>
        <button
          type="button"
          class={["sp-toolbar-btn", @read_mode && "sp-toolbar-btn-active"]}
          phx-click="toggle_read_mode"
          title={
            if @read_mode,
              do: dgettext("screenplays", "Exit read mode"),
              else: dgettext("screenplays", "Read mode")
          }
        >
          <.icon name={if @read_mode, do: "pencil", else: "book-open"} class="size-4" />
        </button>
        <a
          href={
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/#{@screenplay.id}/export/fountain"
          }
          class="sp-toolbar-btn"
          title={dgettext("screenplays", "Export as Fountain")}
          download
        >
          <.icon name="upload" class="size-4" />
        </a>
        <button
          :if={@can_edit}
          type="button"
          class="sp-toolbar-btn"
          title={dgettext("screenplays", "Import Fountain")}
          id="screenplay-import-btn"
          phx-hook="FountainImport"
        >
          <.icon name="download" class="size-4" />
        </button>
        <span class="screenplay-toolbar-separator"></span>
        <%= case @link_status do %>
          <% :unlinked -> %>
            <button
              :if={@can_edit}
              class="sp-sync-btn"
              phx-click="create_flow_from_screenplay"
            >
              <.icon name="git-branch" class="size-3.5" />
              {dgettext("screenplays", "Create Flow")}
            </button>
          <% :linked -> %>
            <button
              class="sp-sync-badge sp-sync-linked"
              phx-click="navigate_to_flow"
            >
              <.icon name="git-branch" class="size-3" />
              {@linked_flow.name}
            </button>
            <button
              :if={@can_edit}
              class="sp-sync-btn"
              phx-click="sync_to_flow"
              title={dgettext("screenplays", "Push screenplay to flow")}
            >
              <.icon name="upload" class="size-3.5" />
              {dgettext("screenplays", "To Flow")}
            </button>
            <button
              :if={@can_edit}
              class="sp-sync-btn"
              phx-click="sync_from_flow"
              title={dgettext("screenplays", "Update screenplay from flow")}
            >
              <.icon name="download" class="size-3.5" />
              {dgettext("screenplays", "From Flow")}
            </button>
            <button
              :if={@can_edit}
              class="sp-sync-btn sp-sync-btn-subtle"
              phx-click="unlink_flow"
            >
              <.icon name="unlink" class="size-3.5" />
            </button>
          <% status when status in [:flow_deleted, :flow_missing] -> %>
            <span class="sp-sync-badge sp-sync-warning">
              <.icon name="alert-triangle" class="size-3" />
              {if status == :flow_deleted,
                do: dgettext("screenplays", "Flow trashed"),
                else: dgettext("screenplays", "Flow missing")}
            </span>
            <button
              :if={@can_edit}
              class="sp-sync-btn sp-sync-btn-subtle"
              phx-click="unlink_flow"
            >
              <.icon name="unlink" class="size-3.5" />
              {dgettext("screenplays", "Unlink")}
            </button>
        <% end %>
      </div>
    </div>
    """
  end
end
