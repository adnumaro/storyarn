import { beforeEach, describe, expect, it, vi } from "vitest";
import { SeoMetadata, syncSeoMetadata } from "../../../js/utils/seo_metadata.js";

function metaContent(selector: string): string | null {
  return document.head.querySelector<HTMLMetaElement>(selector)?.content ?? null;
}

function managedAlternateLinks(): Array<{ href: string; hreflang: string }> {
  return Array.from(
    document.head.querySelectorAll<HTMLLinkElement>(
      'link[rel="alternate"][data-seo-managed="hreflang"]',
    ),
  ).map((element) => ({
    href: element.href,
    hreflang: element.hreflang,
  }));
}

describe("LiveView SEO metadata", () => {
  beforeEach(() => {
    window.history.replaceState({}, "", "/blog");
    document.documentElement.lang = "es";
    document.documentElement.dataset.gettextLocale = "es";
    document.head.innerHTML = `
      <meta name="description" content="Old description">
      <link rel="canonical" href="https://old.example/page">
      <meta property="og:type" content="website">
      <meta property="og:title" content="Old title">
      <meta property="og:description" content="Old description">
      <meta property="og:url" content="https://old.example/page">
      <meta property="og:image" content="https://old.example/image.png">
      <meta name="twitter:title" content="Old title">
      <meta name="twitter:description" content="Old description">
      <meta name="twitter:image" content="https://old.example/image.png">
      <link
        rel="alternate"
        hreflang="en"
        href="https://old.example/blog"
        data-seo-managed="hreflang"
      >
      <link rel="alternate" type="application/rss+xml" href="/feed.xml">
    `;
  });

  it("updates article metadata and removes it when navigating back to a website page", () => {
    const articleUrl = `${window.location.origin}/blog/introducing-storyarn`;

    syncSeoMetadata({
      locale: "en",
      content_locale: "en",
      title: "Introducing Storyarn",
      description: "A connected narrative design platform.",
      canonical_url: `${articleUrl}?preview=true#top`,
      type: "article",
      image_url: `${window.location.origin}/article.png`,
      published_time: "2026-07-14",
      modified_time: "2026-07-15",
      article_tags: ["Storyarn", "Narrative design", "Storyarn", ""],
      alternate_links: [
        { hreflang: "en", href: articleUrl },
        {
          hreflang: "es",
          href: `${window.location.origin}/es/blog/presentamos-storyarn`,
        },
        { hreflang: "x-default", href: articleUrl },
      ],
      json_ld: { "@type": "BlogPosting", headline: "Introducing Storyarn" },
    });

    expect(document.documentElement.lang).toBe("en");
    expect(document.documentElement.dataset.gettextLocale).toBe("en");
    expect(document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]')?.href).toBe(
      articleUrl,
    );
    expect(metaContent('meta[property="og:type"]')).toBe("article");
    expect(metaContent('meta[property="article:published_time"]')).toBe("2026-07-14");
    expect(metaContent('meta[property="article:modified_time"]')).toBe("2026-07-15");
    expect(managedAlternateLinks()).toEqual([
      { href: articleUrl, hreflang: "en" },
      {
        href: `${window.location.origin}/es/blog/presentamos-storyarn`,
        hreflang: "es",
      },
      { href: articleUrl, hreflang: "x-default" },
    ]);
    expect(
      Array.from(document.head.querySelectorAll('meta[property="article:tag"]')).map((element) =>
        element.getAttribute("content"),
      ),
    ).toEqual(["Storyarn", "Narrative design"]);
    expect(
      JSON.parse(document.head.querySelector("#seo-structured-data")?.textContent ?? ""),
    ).toEqual({
      "@type": "BlogPosting",
      headline: "Introducing Storyarn",
    });

    window.history.replaceState({}, "", "/blog");
    syncSeoMetadata({
      locale: "en",
      title: "Storyarn Journal",
      description: "Product thinking from Storyarn.",
      canonical_url: null,
      type: "website",
      image_url: `${window.location.origin}/default.png`,
      published_time: null,
      modified_time: null,
      article_tags: [],
      json_ld: null,
    });

    expect(document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]')?.href).toBe(
      `${window.location.origin}/blog`,
    );
    expect(metaContent('meta[property="og:type"]')).toBe("website");
    expect(document.head.querySelector('meta[property="article:published_time"]')).toBeNull();
    expect(document.head.querySelector('meta[property="article:modified_time"]')).toBeNull();
    expect(document.head.querySelectorAll('meta[property="article:tag"]')).toHaveLength(0);
    expect(document.head.querySelector("#seo-structured-data")).toBeNull();
    expect(managedAlternateLinks()).toEqual([]);
    expect(
      document.head.querySelector<HTMLLinkElement>(
        'link[rel="alternate"][type="application/rss+xml"]',
      )?.href,
    ).toBe(`${window.location.origin}/feed.xml`);
  });

  it("adds noindex on non-indexable pages and removes it on public navigation", () => {
    syncSeoMetadata({ robots: "noindex, follow" });
    expect(metaContent('meta[name="robots"]')).toBe("noindex, follow");

    syncSeoMetadata({ robots: null });
    expect(document.head.querySelector('meta[name="robots"]')).toBeNull();
  });

  it("applies and explicitly clears the Gettext content locale", () => {
    syncSeoMetadata({ locale: "pt-BR", content_locale: "pt_BR" });

    expect(document.documentElement.lang).toBe("pt-BR");
    expect(document.documentElement.dataset.gettextLocale).toBe("pt_BR");

    syncSeoMetadata({ content_locale: null });

    expect(document.documentElement.lang).toBe("pt-BR");
    expect(document.documentElement.dataset.gettextLocale).toBeUndefined();
  });

  it("normalizes and deduplicates localized alternate links", () => {
    syncSeoMetadata({
      alternate_links: [
        {
          hreflang: " en ",
          href: "/blog/introducing-storyarn?preview=true#article",
        },
        {
          hreflang: "en",
          href: "https://duplicate.example/blog/introducing-storyarn",
        },
        {
          hreflang: "es",
          href: `${window.location.origin}/es/blog/presentamos-storyarn?source=en#article`,
        },
        {
          hreflang: "x-default",
          href: "/blog/introducing-storyarn",
        },
        { hreflang: "", href: "/invalid-language" },
        { hreflang: "fr", href: "javascript:alert('unsafe')" },
      ],
    });

    expect(managedAlternateLinks()).toEqual([
      {
        href: `${window.location.origin}/blog/introducing-storyarn`,
        hreflang: "en",
      },
      {
        href: `${window.location.origin}/es/blog/presentamos-storyarn`,
        hreflang: "es",
      },
      {
        href: `${window.location.origin}/blog/introducing-storyarn`,
        hreflang: "x-default",
      },
    ]);
  });

  it("ignores a malformed hook payload without breaking navigation", () => {
    const element = document.createElement("div");
    element.dataset.metadata = "not-json";
    document.body.append(element);

    const hook = { el: element };

    expect(() => SeoMetadata.mounted.call(hook)).not.toThrow();
    expect(metaContent('meta[property="og:title"]')).toBe("Old title");
    SeoMetadata.destroyed.call(hook);
  });

  it("applies navigation metadata and cleans up its deferred hook work", () => {
    const element = document.createElement("div");
    element.dataset.metadata = JSON.stringify({ locale: "es", content_locale: "es" });
    document.body.append(element);

    const hook: {
      el: HTMLElement;
      handleSeoNavigation?: () => void;
      seoNavigationFrame?: number;
    } = { el: element };
    let deferredSync: FrameRequestCallback | undefined;
    const requestAnimationFrame = vi
      .spyOn(window, "requestAnimationFrame")
      .mockImplementation((callback) => {
        deferredSync = callback;
        return 42;
      });
    const cancelAnimationFrame = vi.spyOn(window, "cancelAnimationFrame");
    const removeEventListener = vi.spyOn(window, "removeEventListener");

    SeoMetadata.mounted.call(hook);
    expect(document.documentElement.dataset.gettextLocale).toBe("es");

    element.dataset.metadata = JSON.stringify({ locale: "en", content_locale: "en" });
    window.dispatchEvent(new Event("phx:navigate"));
    deferredSync?.(0);

    expect(document.documentElement.lang).toBe("en");
    expect(document.documentElement.dataset.gettextLocale).toBe("en");

    SeoMetadata.destroyed.call(hook);

    expect(removeEventListener).toHaveBeenCalledWith("phx:navigate", hook.handleSeoNavigation);
    expect(cancelAnimationFrame).toHaveBeenCalledWith(42);

    requestAnimationFrame.mockRestore();
    cancelAnimationFrame.mockRestore();
    removeEventListener.mockRestore();
  });
});
