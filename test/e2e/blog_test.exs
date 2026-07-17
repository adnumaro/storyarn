defmodule StoryarnWeb.E2E.BlogTest do
  @moduledoc """
  Browser coverage for the public blog shell, metadata, and LiveView navigation.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  @moduletag :e2e

  @article_path "/blog/version-control-branching-narratives"
  @spanish_article_path "/es/blog/control-versiones-narrativa-ramificada"
  @spanish_intro_path "/es/blog/presentamos-storyarn"

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
      assert metadata["published"] == "2026-07-17"
      assert metadata["tagCount"] == 4
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
    |> click("#public-language-switcher-trigger")
    |> click("#public-language-switcher-es")
    |> assert_path("/es/blog")
    |> assert_has("html[lang='es']")
    |> assert_has("#blog-featured-post h2", text: "Volver atrás sin romper la historia")
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
    |> assert_has("#blog-post-content",
      text: "Una restauración puede terminar sin errores y aun así romper una historia."
    )
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> click("#public-language-switcher-trigger")
    |> click("#public-language-switcher-en")
    |> assert_path(@article_path)
    |> assert_has("html[lang='en']")
    |> assert_has("#blog-post[lang='en']")
    |> assert_has("#blog-post-content",
      text: "A restore can complete without errors and still break a story."
    )
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
    |> assert_has("#blog-post-content",
      text: "Una restauración puede terminar sin errores y aun así romper una historia."
    )
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
    |> evaluate(history_navigation_expression("forward"))
    |> assert_path(@article_path)
    |> assert_has("html[lang='en']")
    |> evaluate("window.__publicNavigationBlank", fn value -> assert value == false end)
  end

  test "renders the localized article CTA as a separated button and loads the debugger image", %{
    conn: conn
  } do
    conn
    |> visit(@spanish_intro_path)
    |> assert_has("body .phx-connected")
    |> assert_has("#blog-signup-card")
    |> assert_has("#blog-register-cta", text: "Crea tu cuenta de Storyarn")
    |> evaluate(cta_layout_expression(), fn metrics ->
      assert metrics["display"] == "inline-flex"
      assert metrics["height"] >= 44
      assert metrics["contentGap"] >= 24
      refute metrics["backgroundColor"] in ["rgba(0, 0, 0, 0)", "transparent"]
      assert metrics["contrastRatio"] >= 4.5
      assert metrics["iconCenterDelta"] <= 1
    end)
    |> unwrap(fn %{frame_id: frame_id} ->
      assert {:ok, _} =
               PlaywrightEx.Frame.hover(frame_id,
                 selector: "#blog-register-cta",
                 timeout: 10_000
               )
    end)
    |> evaluate("new Promise((resolve) => window.setTimeout(resolve, 250))")
    |> evaluate(cta_layout_expression(), fn metrics ->
      assert metrics["contrastRatio"] >= 4.5
    end)
    |> evaluate(debug_image_expression(), fn image ->
      assert image["complete"] == true
      assert image["naturalWidth"] > 0
      assert image["naturalHeight"] > 0
      assert_in_delta image["aspectRatio"], 16 / 9, 0.01
    end)
    |> click("#blog-register-cta")
    |> assert_path("/users/register")
    |> assert_has("html[lang='es']")
    |> evaluate("window.location.search", fn search -> assert search == "?locale=es" end)
  end

  test "localized article links preserve the URL-authoritative locale", %{conn: conn} do
    conn
    |> visit(@spanish_intro_path)
    |> assert_has("body .phx-connected")
    |> evaluate(cross_surface_blank_observer_expression())
    |> click("#blog-post-content a[href='/es/docs/world-building/sheets-overview']")
    |> assert_path("/es/docs/world-building/sheets-overview")
    |> assert_has("html[lang='es']")
    |> evaluate("window.__crossSurfaceNavigationBlank", fn value -> assert value == false end)
    |> click("#docs-language-switcher-trigger")
    |> assert_has("#docs-language-switcher-es[aria-current='page'][lang='es']")
    |> assert_has("#docs-language-switcher-en[href='/docs/world-building/sheets-overview'][hreflang='en']")
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

  defp cta_layout_expression do
    """
    (() => {
      const card = document.querySelector('#blog-signup-card');
      const copy = card.querySelector('p:last-of-type');
      const cta = document.querySelector('#blog-register-cta');
      const icon = cta.querySelector('svg');
      const copyRect = copy.getBoundingClientRect();
      const ctaRect = cta.getBoundingClientRect();
      const iconRect = icon.getBoundingClientRect();
      const styles = getComputedStyle(cta);

      const relativeLuminance = (color) => {
        const canvas = document.createElement('canvas');
        canvas.width = 1;
        canvas.height = 1;
        const context = canvas.getContext('2d', { willReadFrequently: true });
        context.fillStyle = color;
        context.fillRect(0, 0, 1, 1);
        const channels = Array.from(context.getImageData(0, 0, 1, 1).data.slice(0, 3));
        const linear = channels.map((channel) => {
          const value = channel / 255;
          return value <= 0.04045
            ? value / 12.92
            : Math.pow((value + 0.055) / 1.055, 2.4);
        });

        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
      };

      const foreground = relativeLuminance(styles.color);
      const background = relativeLuminance(styles.backgroundColor);
      const contrastRatio =
        (Math.max(foreground, background) + 0.05) /
        (Math.min(foreground, background) + 0.05);

      return {
        display: styles.display,
        height: ctaRect.height,
        contentGap: ctaRect.top - copyRect.bottom,
        backgroundColor: styles.backgroundColor,
        contrastRatio,
        iconCenterDelta: Math.abs(
          (iconRect.top + iconRect.height / 2) - (ctaRect.top + ctaRect.height / 2)
        ),
      };
    })()
    """
  end

  defp debug_image_expression do
    """
    new Promise((resolve) => {
      const image = document.querySelector(
        '#blog-post-content img[src="/images/blog/introducing-storyarn-debug-active-node.png"]'
      );

      const readDimensions = () => resolve({
        complete: image.complete,
        naturalWidth: image.naturalWidth,
        naturalHeight: image.naturalHeight,
        aspectRatio: image.naturalWidth / image.naturalHeight,
      });

      image.scrollIntoView({ block: 'center' });

      if (image.complete) {
        requestAnimationFrame(readDimensions);
      } else {
        image.addEventListener('load', readDimensions, { once: true });
        image.addEventListener('error', readDimensions, { once: true });
      }
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
