/**
 * Discover section — lightweight init for text overlay state.
 * Tab clicks and monitor animation are handled by section_scroll.js.
 */

const initDiscoverSection = () => {
  const root = document.querySelector("[data-feature-shell]");

  if (!(root instanceof HTMLElement) || root.dataset.discoverInitialized === "true") {
    return;
  }

  const tabs = Array.from(root.querySelectorAll("[data-feature-tab]"));
  const texts = Array.from(root.querySelectorAll("[data-discover-text]"));

  if (tabs.length === 0) return;

  const initialFeature = root.dataset.activeFeature || tabs[0]?.dataset.featureTab;

  tabs.forEach((tab) => {
    const active = tab.dataset.featureTab === initialFeature;
    tab.classList.toggle("is-active", active);
  });

  texts.forEach((text) => {
    const active = text.dataset.featureTab === initialFeature;
    text.classList.toggle("is-active", active);
  });

  root.dataset.discoverInitialized = "true";
};

initDiscoverSection();
window.addEventListener("phx:page-loading-stop", initDiscoverSection);
