const initDiscoverSection = () => {
  const root = document.querySelector("[data-feature-shell]");

  if (!(root instanceof HTMLElement) || root.dataset.discoverInitialized === "true") {
    return;
  }

  const scrollbox = document.querySelector("[data-feature-scrollbox]");
  const tabs = Array.from(root.querySelectorAll("[data-feature]"));
  const steps = Array.from(root.querySelectorAll("[data-feature-step]"));

  if (tabs.length === 0 || steps.length === 0) {
    return;
  }

  const setActive = (feature) => {
    root.dataset.activeFeature = feature;

    tabs.forEach((tab) => {
      tab.setAttribute("aria-selected", tab.dataset.feature === feature ? "true" : "false");
    });

    steps.forEach((step) => {
      step.classList.toggle("is-active", step.dataset.featureStep === feature);
    });
  };

  let ticking = false;

  const updateFromScroll = () => {
    const bounds =
      scrollbox instanceof HTMLElement
        ? scrollbox.getBoundingClientRect()
        : { top: 0, height: window.innerHeight };
    const targetLine = bounds.top + bounds.height * 0.24;
    let next = steps[0];
    let closest = Number.POSITIVE_INFINITY;

    steps.forEach((step) => {
      const rect = step.getBoundingClientRect();
      const center = rect.top + rect.height / 2;
      const distance = Math.abs(center - targetLine);

      if (distance < closest) {
        closest = distance;
        next = step;
      }
    });

    if (next instanceof HTMLElement && next.dataset.featureStep) {
      setActive(next.dataset.featureStep);
    }

    ticking = false;
  };

  const handleScroll = () => {
    if (ticking) return;

    ticking = true;
    window.requestAnimationFrame(updateFromScroll);
  };

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const feature = tab.dataset.feature;
      const target = root.querySelector(`[data-feature-step="${feature}"]`);

      if (!(target instanceof HTMLElement) || !feature) {
        return;
      }

      setActive(feature);

      if (scrollbox instanceof HTMLElement) {
        const top =
          scrollbox.scrollTop +
          (target.getBoundingClientRect().top - scrollbox.getBoundingClientRect().top) -
          scrollbox.clientHeight * 0.16;

        scrollbox.scrollTo({ top, behavior: "smooth" });
      } else {
        target.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    });
  });

  (scrollbox instanceof HTMLElement ? scrollbox : window).addEventListener("scroll", handleScroll, {
    passive: true,
  });
  window.addEventListener("resize", handleScroll);

  root.dataset.discoverInitialized = "true";
  setActive(root.dataset.activeFeature || "dashboard");
  updateFromScroll();
};

initDiscoverSection();
window.addEventListener("phx:page-loading-stop", initDiscoverSection);
