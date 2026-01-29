defmodule StoryarnWeb.PageController do
  use StoryarnWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
