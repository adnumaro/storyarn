defmodule StoryarnWeb.E2E.BlogTest do
  @moduledoc """
  Browser coverage for the public blog shell, metadata, and LiveView navigation.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  @moduletag :e2e

  @article_path "/blog/introducing-storyarn"
  @spanish_article_path "/es/blog/presentamos-storyarn"

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
      assert metadata["canonicalPath"] == @article_path
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
      assert metadata["canonicalPath"] == "/blog"
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

  test "switches between canonical article translations without a blank frame", %{conn: conn} do
    conn
    |> visit("/blog")
    |> assert_has("body .phx-connected")
    |> evaluate(navigation_blank_observer_expression())
    |> click("#public-language-switcher-es")
    |> assert_path("/es/blog")
    |> assert_has("html[lang='es']")
    |> assert_has("#blog-featured-post h2", text: "Presentamos Storyarn")
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> evaluate(localized_metadata_expression(), fn metadata ->
      assert metadata["canonicalPath"] == "/es/blog"
      assert metadata["englishPath"] == "/blog"
      assert metadata["spanishPath"] == "/es/blog"
      assert metadata["defaultPath"] == "/blog"
      assert metadata["language"] == "es"
      assert metadata["liveSeoCount"] == 1
    end)
    |> click("#blog-featured-post a[href='#{@spanish_article_path}']")
    |> assert_path(@spanish_article_path)
    |> assert_has("#blog-post[lang='es']")
    |> assert_has("#blog-post-content", text: "Notion o World Anvil")
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> click("#public-language-switcher-en")
    |> assert_path(@article_path)
    |> assert_has("html[lang='en']")
    |> assert_has("#blog-post[lang='en']")
    |> assert_has("#blog-post-content", text: "Notion or World Anvil")
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> evaluate(localized_metadata_expression(), fn metadata ->
      assert metadata["canonicalPath"] == @article_path
      assert metadata["englishPath"] == @article_path
      assert metadata["spanishPath"] == @spanish_article_path
      assert metadata["defaultPath"] == @article_path
      assert metadata["language"] == "en"
      assert metadata["structuredDataLanguage"] == "en"
      assert metadata["liveSeoCount"] == 1
    end)
    |> evaluate(history_navigation_expression("back"))
    |> assert_path(@spanish_article_path)
    |> assert_has("html[lang='es']")
    |> assert_has("#blog-post-content", text: "Notion o World Anvil")
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> evaluate(history_navigation_expression("forward"))
    |> assert_path(@article_path)
    |> assert_has("html[lang='en']")
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
  end

  test "localized article links preserve the URL-authoritative locale", %{conn: conn} do
    conn
    |> visit("/blog")
    |> assert_has("body .phx-connected")
    |> evaluate(cross_surface_blank_observer_expression())
    |> click("#public-language-switcher-es")
    |> assert_path("/es/blog")
    |> click("#blog-featured-post a[href='#{@spanish_article_path}']")
    |> assert_path(@spanish_article_path)
    |> click("#blog-post-content a[href='/es/docs/world-building/sheets-overview']")
    |> assert_path("/es/docs/world-building/sheets-overview")
    |> assert_has("html[lang='es']")
    |> evaluate("window.__crossSurfaceNavigationBlank", fn value -> assert value == false end)
    |> click("#docs-language-switcher summary")
    |> assert_has("#docs-language-switcher [aria-current='page'][lang='es']")
    |> assert_has("#docs-language-switcher a[href='/docs/world-building/sheets-overview'][hreflang='en']")
  end

  test "hands Spanish off to auth and returns to the localized landing without reloading", %{conn: conn} do
    conn
    |> visit("/es/blog")
    |> assert_has("body .phx-connected")
    |> evaluate("document.documentElement.dataset.navigationSentinel = 'kept'")
    |> evaluate(cross_surface_blank_observer_expression())
    |> click("#public-header a[href='/users/register?locale=es']")
    |> assert_path("/users/register")
    |> assert_has("html[lang='es']")
    |> assert_has("#auth-layout-shell")
    |> evaluate("window.location.search", fn search -> assert search == "?locale=es" end)
    |> evaluate("document.documentElement.dataset.navigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> evaluate("window.__crossSurfaceNavigationBlank", fn value -> assert value == false end)
    |> click("#auth-layout-shell a[href='/es']")
    |> assert_path("/es")
    |> assert_has("html[lang='es']")
    |> assert_has("#landing-page[data-v-app]")
    |> evaluate("document.documentElement.dataset.navigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> evaluate("window.__crossSurfaceNavigationBlank", fn value -> assert value == false end)
  end

  defp article_metadata_expression do
    """
    ({
      type: document.querySelector('meta[property="og:type"]')?.content ?? null,
      canonicalPath: document.querySelector('link[rel="canonical"]')
        ? new URL(document.querySelector('link[rel="canonical"]').href).pathname
        : null,
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

  defp cross_surface_blank_observer_expression do
    """
    (() => {
      window.__crossSurfaceNavigationBlank = false;
      const inspect = () => {
        const surface = document.querySelector(
          '#public-main > :first-child, #docs-main, #auth-layout-shell'
        );

        if (!surface || (surface.children.length === 0 && surface.textContent.trim() === '')) {
          window.__crossSurfaceNavigationBlank = true;
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

  defp localized_metadata_expression do
    """
    ({
      canonicalPath: document.querySelector('link[rel="canonical"]')
        ? new URL(document.querySelector('link[rel="canonical"]').href).pathname
        : null,
      englishPath: document.querySelector('link[rel="alternate"][hreflang="en"]')
        ? new URL(document.querySelector('link[rel="alternate"][hreflang="en"]').href).pathname
        : null,
      spanishPath: document.querySelector('link[rel="alternate"][hreflang="es"]')
        ? new URL(document.querySelector('link[rel="alternate"][hreflang="es"]').href).pathname
        : null,
      defaultPath: document.querySelector('link[rel="alternate"][hreflang="x-default"]')
        ? new URL(document.querySelector('link[rel="alternate"][hreflang="x-default"]').href).pathname
        : null,
      language: document.documentElement.lang,
      structuredDataLanguage: (() => {
        const node = document.head.querySelector('#seo-structured-data');
        return node ? JSON.parse(node.textContent).inLanguage ?? null : null;
      })(),
      liveSeoCount: document.querySelectorAll('#live-seo-metadata').length,
    })
    """
  end

  defp history_navigation_expression(direction) do
    """
    new Promise((resolve) => {
      window.addEventListener('popstate', () => resolve(true), { once: true });
      window.history.#{direction}();
    })
    """
  end
end
