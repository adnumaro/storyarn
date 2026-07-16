defmodule StoryarnWeb.PublicLocaleRedirectController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.PublicURLs

  def default_locale(conn, _params) do
    request_target =
      conn.request_path <> if(conn.query_string == "", do: "", else: "?#{conn.query_string}")

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: PublicURLs.localize_path(request_target, PublicLocales.default_locale()))
  end
end
