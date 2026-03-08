/**
 * Shadow DOM CSS injection utility.
 * Shares a single CSSStyleSheet across all shadow roots and keeps it
 * in sync with Phoenix hot reload by watching for <link> changes.
 */

let sharedSheet = null;
let lastFetchedUrl = null;
let activeRefresh = null;

function isAppCssLink(el) {
  // Match both dev (/app.css) and prod (/app-<digest>.css)
  return el?.tagName === "LINK" && /\/app[\w.-]*\.css/.test(el.getAttribute("href"));
}

function getAppCssUrl() {
  const links = document.querySelectorAll('link[rel="stylesheet"]');
  for (const link of links) {
    if (isAppCssLink(link)) return link.href;
  }
  return null;
}

function hoistPropertyDeclarations(cssText) {
  const propertyBlocks = [];
  const cleaned = cssText.replace(/@property\s+--[\w-]+\s*\{[^}]*\}/g, (match) => {
    propertyBlocks.push(match);
    return "";
  });

  if (propertyBlocks.length > 0) {
    let style = document.head.querySelector("style[data-shadow-properties]");
    if (!style) {
      style = document.createElement("style");
      style.setAttribute("data-shadow-properties", "");
      document.head.appendChild(style);
    }
    style.textContent = propertyBlocks.join("\n");
  }

  return cleaned;
}

function refreshSheet(url) {
  if (activeRefresh) {
    return activeRefresh;
  }

  activeRefresh = (async () => {
    try {
      const response = await fetch(url, { cache: "no-store" });
      const cssText = await response.text();
      const cleaned = hoistPropertyDeclarations(cssText);

      if (sharedSheet) {
        await sharedSheet.replace(cleaned);
      } else {
        const sheet = new CSSStyleSheet();
        sheet.replaceSync(cleaned);
        sharedSheet = sheet;
      }

      lastFetchedUrl = url;
    } catch (err) {
      // biome-ignore lint/suspicious/noConsole: intentional error logging
      console.error("[shadow-styles] refreshSheet failed:", err);
    } finally {
      activeRefresh = null;
    }
    return sharedSheet;
  })();

  return activeRefresh;
}

function watchForCssReload() {
  if (typeof MutationObserver === "undefined") return;

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (
        mutation.type === "attributes" &&
        mutation.attributeName === "href" &&
        isAppCssLink(mutation.target)
      ) {
        refreshSheet(mutation.target.href);
        return;
      }

      for (const node of mutation.addedNodes) {
        if (node.nodeType === Node.ELEMENT_NODE && isAppCssLink(node)) {
          refreshSheet(node.href);
          return;
        }
      }
    }
  });

  observer.observe(document.head, {
    attributes: true,
    attributeFilter: ["href"],
    childList: true,
    subtree: true,
  });
}

watchForCssReload();

// Eagerly start the CSS fetch at module load time. This minimises the window
// between page load and Tailwind being applied to shadow roots, preventing a
// race condition where Rete.js calculates socket positions before the CSS
// changes the layout of socket elements.
const eagerUrl = getAppCssUrl();
if (eagerUrl) {
  refreshSheet(eagerUrl);
}

/**
 * Waits for the current CSS fetch to complete (if one is in progress).
 * Call this before measuring socket positions to ensure Tailwind styles
 * are already applied to all shadow roots.
 */
export async function waitForCss() {
  if (activeRefresh) {
    await activeRefresh;
  } else if (!sharedSheet) {
    const url = getAppCssUrl();
    if (url) await refreshSheet(url);
  }
}

export async function adoptTailwind(shadowRoot) {
  const currentUrl = getAppCssUrl();
  if (!currentUrl) return;

  const needsFetch = !sharedSheet || currentUrl !== lastFetchedUrl;

  if (needsFetch) {
    await refreshSheet(currentUrl);
  }

  const sheet = sharedSheet;
  if (!sheet) return;

  if (shadowRoot.adoptedStyleSheets.includes(sheet)) return;

  shadowRoot.adoptedStyleSheets = [sheet, ...shadowRoot.adoptedStyleSheets];
}
