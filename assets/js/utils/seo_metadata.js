const managedMetaTags = [
  ['meta[name="description"]', "name", "description", "description"],
  ['meta[property="og:type"]', "property", "og:type", "type"],
  ['meta[property="og:title"]', "property", "og:title", "title"],
  ['meta[property="og:description"]', "property", "og:description", "description"],
  ['meta[property="og:image"]', "property", "og:image", "image_url"],
  ['meta[name="twitter:title"]', "name", "twitter:title", "title"],
  ['meta[name="twitter:description"]', "name", "twitter:description", "description"],
  ['meta[name="twitter:image"]', "name", "twitter:image", "image_url"],
];

const optionalArticleMetaTags = [
  ['meta[property="article:published_time"]', "article:published_time", "published_time"],
  ['meta[property="article:modified_time"]', "article:modified_time", "modified_time"],
];

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function currentCanonicalUrl() {
  return `${window.location.origin}${window.location.pathname}`;
}

function canonicalUrl(value) {
  const explicitUrl = nonEmptyString(value);

  if (!explicitUrl) return currentCanonicalUrl();

  try {
    const url = new URL(explicitUrl, window.location.origin);
    url.search = "";
    url.hash = "";
    return url.href;
  } catch {
    return currentCanonicalUrl();
  }
}

function upsertMeta(selector, attribute, attributeValue, content) {
  let element = document.head.querySelector(selector);
  const normalizedContent = nonEmptyString(content);

  if (!normalizedContent) {
    element?.remove();
    return;
  }

  if (!element) {
    element = document.createElement("meta");
    element.setAttribute(attribute, attributeValue);
    document.head.append(element);
  }

  element.setAttribute("content", normalizedContent);
}

function syncCanonical(value) {
  let element = document.head.querySelector('link[rel="canonical"]');

  if (!element) {
    element = document.createElement("link");
    element.setAttribute("rel", "canonical");
    document.head.append(element);
  }

  const url = canonicalUrl(value);
  element.setAttribute("href", url);
  upsertMeta('meta[property="og:url"]', "property", "og:url", url);
}

function syncArticleTags(tags) {
  document.head.querySelectorAll('meta[property="article:tag"]').forEach((element) => {
    element.remove();
  });

  if (!Array.isArray(tags)) return;

  const uniqueTags = new Set(tags.map(nonEmptyString).filter(Boolean));

  for (const tag of uniqueTags) {
    const element = document.createElement("meta");
    element.setAttribute("property", "article:tag");
    element.setAttribute("content", tag);
    document.head.append(element);
  }
}

function syncStructuredData(value) {
  let element = document.head.querySelector("#seo-structured-data");
  const isObject = value && typeof value === "object" && !Array.isArray(value);

  if (!isObject) {
    element?.remove();
    return;
  }

  if (!element) {
    element = document.createElement("script");
    element.id = "seo-structured-data";
    element.setAttribute("type", "application/ld+json");
    document.head.append(element);
  }

  element.textContent = JSON.stringify(value);
}

export function syncSeoMetadata(metadata) {
  if (!metadata || typeof metadata !== "object") return;

  const locale = nonEmptyString(metadata.locale);
  if (locale) document.documentElement.lang = locale;

  for (const [selector, attribute, attributeValue, key] of managedMetaTags) {
    upsertMeta(selector, attribute, attributeValue, metadata[key]);
  }

  syncCanonical(metadata.canonical_url);

  for (const [selector, property, key] of optionalArticleMetaTags) {
    upsertMeta(selector, "property", property, metadata[key]);
  }

  syncArticleTags(metadata.article_tags);
  syncStructuredData(metadata.json_ld);
}

function syncFromElement(element) {
  try {
    syncSeoMetadata(JSON.parse(element.dataset.metadata ?? ""));
  } catch {
    // A malformed payload must not break LiveView navigation.
  }
}

export const SeoMetadata = {
  mounted() {
    this.handleSeoNavigation = () => {
      this.seoNavigationFrame = window.requestAnimationFrame(() => {
        if (this.el.isConnected) syncFromElement(this.el);
      });
    };

    window.addEventListener("phx:navigate", this.handleSeoNavigation);
    syncFromElement(this.el);
  },
  updated() {
    syncFromElement(this.el);
  },
  destroyed() {
    window.removeEventListener("phx:navigate", this.handleSeoNavigation);
    if (this.seoNavigationFrame) window.cancelAnimationFrame(this.seoNavigationFrame);
  },
};
