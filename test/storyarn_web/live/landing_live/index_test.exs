defmodule StoryarnWeb.LandingLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Storyarn.Accounts.WaitlistEntry
  alias Storyarn.Repo

  test "joins the waitlist through the landing LiveView event with email only", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "join_waitlist", %{
      "email" => "WAITLIST@example.com"
    })

    entry = Repo.get_by!(WaitlistEntry, email: "waitlist@example.com")
    assert entry.profession == nil
    assert entry.primary_interest == nil
    assert entry.discovery_source == nil
    assert entry.current_tool == nil
  end

  test "saves optional waitlist details after joining", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "join_waitlist", %{
      "email" => "waitlist-details@example.com"
    })

    render_hook(view, "save_waitlist_details", %{
      "profession" => "narrative_designer",
      "primary_interest" => "game_narrative",
      "discovery_source" => "search",
      "current_tool" => "articy_draft"
    })

    entry = Repo.get_by!(WaitlistEntry, email: "waitlist-details@example.com")
    assert entry.profession == "narrative_designer"
    assert entry.primary_interest == "game_narrative"
    assert entry.discovery_source == "search"
    assert entry.current_tool == "articy_draft"
  end

  test "renders the public landing", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    landing = LiveVue.Test.get_vue(view, name: "live/public/landing/PublicLanding")

    assert landing.props["is-logged-in"] == false
    assert html =~ ~s(data-inject="public-layout")
  end
end
