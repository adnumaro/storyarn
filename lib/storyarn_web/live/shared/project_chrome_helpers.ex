defmodule StoryarnWeb.Live.Shared.ProjectChromeHelpers do
  @moduledoc """
  Helpers shared by every page LV that renders the `ProjectShell` chrome.

  - `forward_main_sidebar/3` — forwards `main_sidebar_*` events from
    `LeftToolbar.vue` (rendered inline by `ProjectShell`, so events land
    in the page LV) to the per-tool sidebar LV via the shell PubSub topic.
  - `initial_online_users/1` — snapshot of current presence for the
    initial render; `PresenceLive` broadcasts updates on every join/leave.
  """

  alias Phoenix.LiveView.Socket
  alias Storyarn.Collaboration

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
