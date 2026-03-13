defmodule StoryarnWeb.Components.Sidebar.DraftList do
  @moduledoc """
  Flat list of the current user's active drafts, rendered at the bottom of the tree panel.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  alias Phoenix.LiveView.JS
  import StoryarnWeb.Components.CoreComponents

  @stale_days 30

  attr :my_drafts, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :renaming_draft, :map, default: nil

  def drafts_section(assigns) do
    assigns = assign(assigns, :count, length(assigns.my_drafts))

    ~H"""
    <div :if={@count > 0} class="border-t border-base-300 pt-2 mt-2">
      <details open>
        <summary class="flex items-center gap-1.5 cursor-pointer select-none px-1 py-1 text-xs font-medium text-base-content/60 hover:text-base-content/80">
          <.icon name="git-branch" class="size-3.5" />
          <span class="flex-1">{dgettext("drafts", "My Drafts")}</span>
          <span class="badge badge-xs badge-ghost">{@count}</span>
        </summary>
        <ul class="mt-1 space-y-0.5">
          <li :for={draft <- @my_drafts}>
            <.draft_item
              draft={draft}
              workspace={@workspace}
              project={@project}
              renaming={@renaming_draft && @renaming_draft.id == draft.id}
            />
          </li>
        </ul>
      </details>
    </div>
    """
  end

  attr :draft, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :renaming, :boolean, default: false

  defp draft_item(assigns) do
    assigns =
      assigns
      |> assign(:stale?, stale?(assigns.draft))
      |> assign(:icon, entity_icon(assigns.draft.entity_type))
      |> assign(:href, draft_href(assigns.workspace, assigns.project, assigns.draft))
      |> assign(:relative_time, relative_time(assigns.draft.last_edited_at))
      |> assign(:display_source_name, assigns.draft.source_name || dgettext("drafts", "Deleted"))

    ~H"""
    <div class="group flex items-center gap-1.5 px-1.5 py-1 rounded hover:bg-base-300/50 text-sm">
      <.icon name={@icon} class="size-3.5 opacity-50 shrink-0" />
      <%= if @renaming do %>
        <form phx-submit="submit_rename_draft" class="flex-1 flex items-center gap-1">
          <input type="hidden" name="draft_id" value={@draft.id} />
          <input
            type="text"
            name="name"
            value={@draft.name}
            class="input input-xs input-bordered flex-1 min-w-0"
            autofocus
            phx-key="Escape"
            phx-keydown={JS.push("cancel_rename_draft")}
          />
          <button type="submit" class="btn btn-ghost btn-xs btn-square">
            <.icon name="check" class="size-3" />
          </button>
        </form>
      <% else %>
        <.link patch={@href} class="flex-1 truncate hover:text-primary">
          {@draft.name}
        </.link>
        <span
          :if={@stale?}
          class="badge badge-xs badge-warning shrink-0"
          title={dgettext("drafts", "Stale draft")}
        >
          {dgettext("drafts", "stale")}
        </span>
        <div class="hidden group-hover:flex items-center gap-0.5 shrink-0">
          <button
            type="button"
            phx-click="rename_draft_inline"
            phx-value-draft-id={@draft.id}
            class="btn btn-ghost btn-xs btn-square"
            title={dgettext("drafts", "Rename")}
          >
            <.icon name="pencil" class="size-3" />
          </button>
          <button
            type="button"
            phx-click={show_modal("discard-draft-list-#{@draft.id}")}
            class="btn btn-ghost btn-xs btn-square text-error"
            title={dgettext("drafts", "Discard")}
          >
            <.icon name="trash-2" class="size-3" />
          </button>
        </div>
        <span class="text-xs text-base-content/40 shrink-0 group-hover:hidden">{@relative_time}</span>
      <% end %>

      <.confirm_modal
        id={"discard-draft-list-#{@draft.id}"}
        title={dgettext("drafts", "Discard draft?")}
        message={dgettext("drafts", "This draft will be permanently deleted. This cannot be undone.")}
        confirm_text={dgettext("drafts", "Discard")}
        confirm_variant="error"
        icon="trash-2"
        on_confirm={JS.push("discard_draft_from_list", value: %{draft_id: @draft.id})}
      />
    </div>
    <div class="px-1.5 mb-1">
      <span class="text-xs text-base-content/40">
        {dgettext("drafts", "from")} <span class="font-medium">{@display_source_name}</span>
      </span>
    </div>
    """
  end

  defp entity_icon("flow"), do: "git-branch"
  defp entity_icon("sheet"), do: "file-text"
  defp entity_icon("scene"), do: "map"
  defp entity_icon(_), do: "file"

  defp stale?(%{last_edited_at: last_edited_at}) when not is_nil(last_edited_at) do
    DateTime.diff(DateTime.utc_now(), last_edited_at, :day) >= @stale_days
  end

  defp stale?(_), do: false

  defp draft_href(workspace, project, %{entity_type: "flow"} = draft) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{draft.source_entity_id}/drafts/#{draft.id}"
  end

  defp draft_href(workspace, project, %{entity_type: "sheet"} = draft) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{draft.source_entity_id}/drafts/#{draft.id}"
  end

  defp draft_href(workspace, project, %{entity_type: "scene"} = draft) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{draft.source_entity_id}/drafts/#{draft.id}"
  end

  defp draft_href(workspace, project, _draft) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}"
  end

  defp relative_time(nil), do: ""

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> dgettext("drafts", "just now")
      diff < 3600 -> dgettext("drafts", "%{count}m ago", count: div(diff, 60))
      diff < 86_400 -> dgettext("drafts", "%{count}h ago", count: div(diff, 3600))
      true -> dgettext("drafts", "%{count}d ago", count: div(diff, 86_400))
    end
  end
end
