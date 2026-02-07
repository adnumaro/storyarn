defmodule StoryarnWeb.SheetLive.Components.BacklinksSection do
  @moduledoc """
  LiveComponent for displaying backlinks to a sheet.
  Shows sheets and flows that reference the current sheet.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
        <.icon name="arrow-left" class="size-5" />
        {gettext("Backlinks")}
        <%= if @backlinks && length(@backlinks) > 0 do %>
          <span class="badge badge-sm">{length(@backlinks)}</span>
        <% end %>
      </h2>

      <%= if is_nil(@backlinks) do %>
        <.loading_placeholder />
      <% else %>
        <%= if @backlinks == [] do %>
          <.empty_backlinks_state />
        <% else %>
          <div class="space-y-2">
            <.backlink_row :for={backlink <- @backlinks} backlink={backlink} />
          </div>
        <% end %>
      <% end %>
    </section>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:backlinks, fn -> nil end)

    socket =
      if is_nil(socket.assigns.backlinks) do
        load_backlinks(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  defp load_backlinks(socket) do
    backlinks =
      Sheets.get_backlinks_with_sources(
        "sheet",
        socket.assigns.sheet.id,
        socket.assigns.project.id
      )

    assign(socket, :backlinks, backlinks)
  end

  # ===========================================================================
  # Function Components
  # ===========================================================================

  defp loading_placeholder(assigns) do
    ~H"""
    <div class="flex items-center justify-center p-8">
      <span class="loading loading-spinner loading-md"></span>
    </div>
    """
  end

  defp empty_backlinks_state(assigns) do
    ~H"""
    <div class="bg-base-200/50 rounded-lg p-8 text-center">
      <.icon name="link" class="size-12 mx-auto text-base-content/30 mb-4" />
      <p class="text-base-content/70 mb-2">{gettext("No backlinks yet")}</p>
      <p class="text-sm text-base-content/50">
        {gettext("Sheets and flows that reference this sheet will appear here.")}
      </p>
    </div>
    """
  end

  attr :backlink, :map, required: true

  defp backlink_row(assigns) do
    source_info = assigns.backlink.source_info

    assigns =
      assigns
      |> assign(:source_info, source_info)
      |> assign(:is_sheet, source_info[:type] == :sheet)
      |> assign(:is_flow, source_info[:type] == :flow)

    ~H"""
    <div class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-200/50 group">
      <%!-- Source type icon --%>
      <div class={[
        "flex-shrink-0 size-8 rounded flex items-center justify-center",
        @is_sheet && "bg-primary/20 text-primary",
        @is_flow && "bg-secondary/20 text-secondary"
      ]}>
        <.icon :if={@is_sheet} name="file-text" class="size-4" />
        <.icon :if={@is_flow} name="git-branch" class="size-4" />
      </div>

      <div class="flex-1 min-w-0">
        <%!-- Source name --%>
        <div class="flex items-center gap-2">
          <span :if={@is_sheet} class="font-medium truncate">
            {@source_info.sheet_name}
          </span>
          <span :if={@is_flow} class="font-medium truncate">
            {@source_info.flow_name}
          </span>
          <%= if @is_sheet && @source_info.sheet_shortcut do %>
            <span class="text-xs text-base-content/50">#{@source_info.sheet_shortcut}</span>
          <% end %>
          <%= if @is_flow && @source_info.flow_shortcut do %>
            <span class="text-xs text-base-content/50">#{@source_info.flow_shortcut}</span>
          <% end %>
        </div>

        <%!-- Context (block/field info) --%>
        <div class="text-sm text-base-content/60">
          <%= if @is_sheet do %>
            <span class="badge badge-xs badge-ghost mr-1">{@source_info.block_type}</span>
            <span>{@source_info.block_label}</span>
          <% end %>
          <%= if @is_flow do %>
            <span class="badge badge-xs badge-ghost mr-1">{@source_info.node_type}</span>
          <% end %>
        </div>
      </div>

      <%!-- Timestamp --%>
      <div class="text-xs text-base-content/40">
        {Calendar.strftime(@backlink.inserted_at, "%b %d")}
      </div>
    </div>
    """
  end
end
