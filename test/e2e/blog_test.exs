defmodule StoryarnWeb.E2E.BlogTest do
  @moduledoc """
  Browser coverage for the public blog shell, metadata, and LiveView navigation.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  @moduletag :e2e

  @article_path "/blog/introducing-storyarn"

  test "keeps one public shell and updates SEO metadata without document reloads", %{conn: conn} do
    conn
    |> visit("/blog")
    |> assert_has("body .phx-connected")
    |> assert_has("#public-header")
    |> assert_has("#public-footer")
    |> evaluate("document.documentElement.dataset.navigationSentinel = 'kept'")
    |> evaluate(navigation_blank_observer_expression())
    |> click("#blog-featured-post a[href='#{@article_path}']")
    |> assert_path(@article_path)
    |> assert_has("#blog-post[lang='en']")
    |> assert_has("#blog-post-hero")
    |> evaluate("document.documentElement.dataset.navigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> evaluate(article_metadata_expression(), fn metadata ->
      assert metadata["type"] == "article"
      assert metadata["canonical"] =~ @article_path
      assert metadata["published"] == "2026-07-14"
      assert metadata["tagCount"] == 3
      assert metadata["hasStructuredData"] == true
    end)
    |> click("#blog-back-link")
    |> assert_path("/blog")
    |> assert_has("#blog-index")
    |> evaluate("document.documentElement.dataset.navigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> evaluate(article_metadata_expression(), fn metadata ->
      assert metadata["type"] == "website"
      assert metadata["canonical"] =~ "/blog"
      assert metadata["published"] == nil
      assert metadata["tagCount"] == 0
      assert metadata["hasStructuredData"] == false
    end)
    |> click("#public-header a[href='/']")
    |> assert_path("/")
    |> assert_has("#landing-page[data-v-app]")
    |> evaluate("document.documentElement.dataset.navigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> click("#public-header a[href='/contact']")
    |> assert_path("/contact")
    |> assert_has("#contact-page[data-v-app]")
    |> evaluate("document.documentElement.dataset.navigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
  end

  test "reopens cookie preferences from the shared public footer", %{conn: conn} do
    conn
    |> visit("/blog")
    |> assert_has("body .phx-connected")
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
  end

  defp article_metadata_expression do
    """
    ({
      type: document.querySelector('meta[property="og:type"]')?.content ?? null,
      canonical: document.querySelector('link[rel="canonical"]')?.href ?? null,
      published: document.querySelector('meta[property="article:published_time"]')?.content ?? null,
      tagCount: document.querySelectorAll('meta[property="article:tag"]').length,
      hasStructuredData: Boolean(document.head.querySelector('#seo-structured-data')),
    })
    """
  end

  defp navigation_blank_observer_expression do
    """
    (() => {
      window.__publicNavigationBlank = false;
      const inspect = () => {
        const main = document.querySelector('#public-main');
        const page = main?.firstElementChild;
        const pageIsEmpty = page && page.children.length === 0 && page.textContent.trim() === '';

        if (!document.querySelector('#public-header') ||
            !document.querySelector('#public-footer') ||
            !page ||
            pageIsEmpty) {
          window.__publicNavigationBlank = true;
        }
      };

      let pendingFrame;
      const inspectNextFrame = () => {
        if (pendingFrame) cancelAnimationFrame(pendingFrame);
        pendingFrame = requestAnimationFrame(inspect);
      };

      new MutationObserver(inspectNextFrame).observe(document.body, {
        childList: true,
        subtree: true,
      });
      inspect();
    })()
    """
  end
end
