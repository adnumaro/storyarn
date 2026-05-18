defmodule StoryarnWeb.LandingLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Storyarn.Accounts.WaitlistEntry
  alias Storyarn.Repo

  test "joins the waitlist through the landing LiveView event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "join_waitlist", %{"email" => "waitlist@example.com"})

    assert Repo.get_by(WaitlistEntry, email: "waitlist@example.com")
  end
end
