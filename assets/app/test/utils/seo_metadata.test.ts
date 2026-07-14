import { beforeEach, describe, expect, it } from "vitest";
import { SeoMetadata, syncSeoMetadata } from "../../../js/utils/seo_metadata.js";

function metaContent(selector: string): string | null {
  return document.head.querySelector<HTMLMetaElement>(selector)?.content ?? null;
}

describe("LiveView SEO metadata", () => {
  beforeEach(() => {
    window.history.replaceState({}, "", "/blog");
    document.documentElement.lang = "es";
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
    `;
  });

  it("updates article metadata and removes it when navigating back to a website page", () => {
    const articleUrl = `${window.location.origin}/blog/introducing-storyarn`;

    syncSeoMetadata({
      locale: "en",
      title: "Introducing Storyarn",
      description: "A connected narrative design platform.",
      canonical_url: `${articleUrl}?preview=true#top`,
      type: "article",
      image_url: `${window.location.origin}/article.png`,
      published_time: "2026-07-14",
      modified_time: "2026-07-15",
      article_tags: ["Storyarn", "Narrative design", "Storyarn", ""],
      json_ld: { "@type": "BlogPosting", headline: "Introducing Storyarn" },
    });

    expect(document.documentElement.lang).toBe("en");
    expect(document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]')?.href).toBe(
      articleUrl,
    );
    expect(metaContent('meta[property="og:type"]')).toBe("article");
    expect(metaContent('meta[property="article:published_time"]')).toBe("2026-07-14");
    expect(metaContent('meta[property="article:modified_time"]')).toBe("2026-07-15");
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
});
