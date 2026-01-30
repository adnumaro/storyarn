defmodule StoryarnWeb.WorkspaceLive.Index do
  @moduledoc """
  LiveView for listing workspaces.

  Redirects to the user's default workspace.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    workspace = Workspaces.get_default_workspace(user)

    if workspace do
      {:ok, push_navigate(socket, to: ~p"/workspaces/#{workspace.slug}")}
    else
      {:ok, push_navigate(socket, to: ~p"/workspaces/new")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center min-h-64">
      <span class="loading loading-spinner loading-lg"></span>
    </div>
    """
  end
end
