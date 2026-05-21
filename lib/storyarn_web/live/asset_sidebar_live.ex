defmodule StoryarnWeb.AssetSidebarLive do
  @moduledoc """
  Assets-specific left sidebar LiveView.

  Owns library-wide filters and search for the assets dashboard. The asset grid
  stays in `AssetLive.Index`; this sticky child broadcasts filter changes over
  the project shell topic so the page LiveView can reload its collection.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @asset_filters ~w(all image audio file)

  @impl true
  def mount(_params, session, socket) do
    if locale = session["locale"], do: Gettext.put_locale(Storyarn.Gettext, locale)

    project_id = session["project_id"]

    socket =
      socket
      |> assign(:project_id, project_id)
      |> assign(:active_tool, session["active_tool"] || "assets")
      |> assign(:dashboard_url, session["dashboard_url"])
      |> assign(:main_sidebar_open, true)
      |> assign(:filter, session["filter"] || "all")
      |> assign(:search, session["search"] || "")
      |> assign(:type_counts, count_assets(project_id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, shell_topic(project_id))
      Collaboration.subscribe_changes({:assets, project_id})
    end

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.vue
        v-component="live/assets/sidebar/AssetsSidebar"
        v-socket={@socket}
        id="assets-sidebar"
        main-sidebar-open={@main_sidebar_open}
        active-tool={@active_tool}
        dashboard-url={@dashboard_url}
        on-dashboard={true}
        sidebar-props={
          %{
            filter: @filter,
            search: @search,
            typeCounts: @type_counts
          }
        }
      />
    </div>
    """
  end

  @impl true
  def handle_event("filter_assets", %{"type" => filter}, socket) when filter in @asset_filters do
    socket = assign(socket, :filter, filter)
    broadcast_filters(socket)

    {:noreply, socket}
  end

  def handle_event("search_assets", %{"search" => search}, socket) do
    socket = assign(socket, :search, search || "")
    broadcast_filters(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:remote_change, _action, _payload}, socket) do
    {:noreply, assign(socket, :type_counts, count_assets(socket.assigns.project_id))}
  end

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp broadcast_filters(socket) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      shell_topic(socket.assigns.project_id),
      {:asset_filters_changed, %{filter: socket.assigns.filter, search: socket.assigns.search}}
    )
  end

  defp count_assets(nil), do: %{}
  defp count_assets(project_id), do: Assets.count_assets_by_type(project_id)

  defp shell_topic(project_id), do: ProjectChromeHelpers.shell_topic(project_id)
end
