defmodule StoryarnWeb.E2E.BlogTest do
  @moduledoc """
  Browser coverage for the public blog shell and article navigation.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  @moduletag :e2e

  test "navigates from the index to an article and reopens cookie preferences", %{conn: conn} do
    conn
    |> visit("/blog")
    |> assert_has("body .phx-connected")
    |> assert_has("#blog-index")
    |> unwrap(fn %{frame_id: frame_id} ->
      assert {:ok, _element} =
               PlaywrightEx.Frame.wait_for_selector(frame_id,
                 selector: "#flash-group-cookie-consent[data-v-app]",
                 state: "attached",
                 timeout: 10_000
               )
    end)
    |> click("#public-manage-cookies")
    |> assert_has("[role='dialog'][aria-modal='true']")
    |> click_button("Save preferences")
    |> click("#public-manage-cookies")
    |> assert_has("[role='dialog'][aria-modal='true']")
    |> click_button("Save preferences")
    |> click("#blog-posts a[href='/blog/test-branching-dialogue-before-export']")
    |> assert_path("/blog/test-branching-dialogue-before-export")
    |> assert_has("#blog-post[lang='en']")
    |> assert_has("#blog-post-content")
  end
end
