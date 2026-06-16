defmodule TestWaitlist do
  @moduledoc false
  def run do
    {:ok, view, _html} =
      Phoenix.LiveViewTest.live_isolated(StoryarnWeb.Endpoint, StoryarnWeb.LandingLive.Index)

    Phoenix.LiveViewTest.render_hook(view, "join_waitlist", %{
      "email" => "test_lv@gmail.com",
      "profession" => "narrative_designer",
      "primary_interest" => "game_narrative",
      "discovery_source" => "search",
      "current_tool" => "none"
    })

    IO.puts("DONE")
  end
end

TestWaitlist.run()
