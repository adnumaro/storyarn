defmodule StoryarnWeb.BlogRedirectController do
  @moduledoc false

  use StoryarnWeb, :controller

  def legacy_post(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/blog/introducing-storyarn")
  end
end
