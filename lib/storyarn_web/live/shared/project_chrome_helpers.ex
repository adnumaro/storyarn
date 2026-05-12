defmodule StoryarnWeb.Live.Shared.ProjectChromeHelpers do
  @moduledoc """
  Helpers shared by every page LV that renders project chrome.

  - `forward_main_sidebar/3` — forwards `main_sidebar_*` events from
    `ProjectNavbarContext.vue` to the per-tool sidebar LV via the shell PubSub
    topic.
  - `initial_online_users/1` — snapshot of current presence for the
    initial render; `PresenceLive` broadcasts updates on every join/leave.
  - `build_urls/2` — URL map consumed by the project chrome Vue boundary.
  """

  use StoryarnWeb, :verified_routes

  alias Phoenix.LiveView.Socket
  alias Storyarn.Collaboration

  @tools [
    %{key: :dashboard, section: "dashboard"},
    %{key: :sheets, section: "sheets"},
    %{key: :flows, section: "flows"},
    %{key: :scenes, section: "scenes"},
    %{key: :assets, section: "assets"},
    %{key: :localization, section: "localization"}
  ]

  defp tool_path(workspace, project, "dashboard"), do: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}"

  defp tool_path(workspace, project, "sheets"), do: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets"

  defp tool_path(workspace, project, "flows"), do: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows"

  defp tool_path(workspace, project, "scenes"), do: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes"

  defp tool_path(workspace, project, "assets"), do: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/assets"

  defp tool_path(workspace, project, "localization"),
    do: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/localization"

  @doc """
  Build the project chrome URL map server-side.
  """
  def build_urls(workspace, project) do
    tool_urls =
      Map.new(@tools, fn tool ->
        {Atom.to_string(tool.key), tool_path(workspace, project, tool.section)}
      end)

    %{
      workspace: ~p"/workspaces/#{workspace.slug}",
      projectSettings: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/settings",
      trash: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/settings/trash",
      accountSettings: ~p"/users/settings",
      workspaces: ~p"/workspaces",
      logout: ~p"/users/log-out",
      tools: tool_urls
    }
  end

  @doc """
  Build the shell topic string for a given project id.
  """
  @spec shell_topic(integer() | binary()) :: String.t()
  def shell_topic(project_id), do: "project:#{project_id}:shell"

  @doc """
  Forward a `main_sidebar_*` event onto the shell topic as a
  `{:toolbar_event, event, params}` tuple so the active sidebar LV picks
  it up.
  """
  @spec forward_main_sidebar(Socket.t(), String.t(), map()) ::
          {:noreply, Socket.t()}
  def forward_main_sidebar(socket, event, params) do
    with %{} = project <- socket.assigns[:project] do
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        shell_topic(project.id),
        {:toolbar_event, event, params}
      )
    end

    {:noreply, socket}
  end

  @doc """
  Snapshot the current online users for a project (used for the page LV's
  initial assign before `PresenceLive` broadcasts its first update).
  """
  @spec initial_online_users(integer() | nil) :: list()
  def initial_online_users(nil), do: []

  def initial_online_users(project_id) do
    Collaboration.list_online_users({:project, project_id})
  rescue
    _ -> []
  end
end
