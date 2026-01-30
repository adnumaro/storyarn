defmodule StoryarnWeb.PageController do
  use StoryarnWeb, :controller

  alias Storyarn.Workspaces

  def home(conn, _params) do
    case conn.assigns do
      %{current_scope: %{user: %Storyarn.Accounts.User{} = user}} ->
        redirect_to_workspace(conn, user)

      _ ->
        render(conn, :home)
    end
  end

  defp redirect_to_workspace(conn, user) do
    case Workspaces.get_default_workspace(user) do
      %Workspaces.Workspace{slug: slug} ->
        redirect(conn, to: ~p"/workspaces/#{slug}")

      nil ->
        redirect(conn, to: ~p"/workspaces/new")
    end
  end
end
