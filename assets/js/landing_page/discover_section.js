const initDiscoverSection = () => {
  const root = document.querySelector("[data-feature-shell]");

  if (!(root instanceof HTMLElement) || root.dataset.discoverInitialized === "true") {
    return;
  }

  const scrollbox = root.querySelector("[data-feature-scrollbox]");
  const tabs = Array.from(root.querySelectorAll("[data-feature-tab]"));
  const triggerGroups = Array.from(root.querySelectorAll("[data-feature-triggers]"));
  const triggers = Array.from(root.querySelectorAll("[data-slide-trigger]"));
  const previews = Array.from(root.querySelectorAll("[data-slide-preview]"));
  const slideGroups = Array.from(root.querySelectorAll("[data-feature-group]"));
  const steps = Array.from(root.querySelectorAll("[data-slide]"));

  if (
    !(scrollbox instanceof HTMLElement) ||
      tabs.length === 0 ||
      slideGroups.length === 0 ||
      steps.length === 0
  ) {
    return;
  }

  const getSlidesForFeature = (feature) =>
    steps.filter((step) => step.dataset.featureStep === feature);

  const getSlideById = (feature, slide) =>
    steps.find(
      (step) => step.dataset.featureStep === feature && step.dataset.slide === slide,
    );

  const getDefaultSlide = (feature) => getSlidesForFeature(feature)[0]?.dataset.slide ?? null;

  const scrollboxIsScrollable = () => {
    const styles = window.getComputedStyle(scrollbox);

    return styles.overflowY !== "visible" && scrollbox.scrollHeight > scrollbox.clientHeight + 1;
  };

  const setActive = (feature, slide) => {
    const resolvedSlide = slide ?? getDefaultSlide(feature);

    if (!feature || !resolvedSlide) {
      return;
    }

    root.dataset.activeFeature = feature;
    root.dataset.activeSlide = resolvedSlide;

    tabs.forEach((tab) => {
      const active = tab.dataset.featureTab === feature;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });

    triggerGroups.forEach((group) => {
      const active = group.dataset.featureTriggers === feature;
      group.classList.toggle("is-active", active);
      group.setAttribute("aria-hidden", active ? "false" : "true");
    });

    triggers.forEach((trigger) => {
      const active =
        trigger.dataset.feature === feature && trigger.dataset.slideTarget === resolvedSlide;

      trigger.classList.toggle("is-active", active);
      trigger.setAttribute("aria-pressed", active ? "true" : "false");
    });

    slideGroups.forEach((group) => {
      const active = group.dataset.featureGroup === feature;
      group.classList.toggle("is-active", active);
      group.setAttribute("aria-hidden", active ? "false" : "true");
    });

    steps.forEach((step) => {
      const active =
        step.dataset.featureStep === feature && step.dataset.slide === resolvedSlide;

      step.classList.toggle("is-active", active);
      step.setAttribute("aria-current", active ? "true" : "false");
    });

    previews.forEach((preview) => {
      const active =
        preview.dataset.featurePreview === feature && preview.dataset.slidePreview === resolvedSlide;

      preview.classList.toggle("is-active", active);
      preview.setAttribute("aria-hidden", active ? "false" : "true");
    });
  };

  const scrollToSlide = (feature, slide, behavior = "smooth") => {
    const target = getSlideById(feature, slide);

    if (!(target instanceof HTMLElement)) {
      return;
    }

    if (scrollboxIsScrollable()) {
      const top =
        scrollbox.scrollTop +
        (target.getBoundingClientRect().top - scrollbox.getBoundingClientRect().top);

      scrollbox.scrollTo({ top, behavior });
      return;
    }

    target.scrollIntoView({ behavior, block: "start" });
  };

  let ticking = false;

  const updateFromScroll = () => {
    const activeFeature = root.dataset.activeFeature;
    const featureSlides = getSlidesForFeature(activeFeature);

    if (featureSlides.length === 0) {
      ticking = false;
      return;
    }

    const targetLine = scrollboxIsScrollable()
      ? scrollbox.getBoundingClientRect().top + scrollbox.clientHeight * 0.38
      : window.innerHeight * 0.48;

    let closestSlide = featureSlides[0];
    let closestDistance = Number.POSITIVE_INFINITY;

    featureSlides.forEach((slide) => {
      const rect = slide.getBoundingClientRect();
      const center = rect.top + rect.height / 2;
      const distance = Math.abs(center - targetLine);

      if (distance < closestDistance) {
        closestDistance = distance;
        closestSlide = slide;
      }
    });

    const slideId = closestSlide?.dataset.slide;

    if (slideId) {
      setActive(activeFeature, slideId);
    }

    ticking = false;
  };

  const requestSync = () => {
    if (ticking) {
      return;
    }

    ticking = true;
    window.requestAnimationFrame(updateFromScroll);
  };

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const feature = tab.dataset.featureTab;
      const firstSlide = getDefaultSlide(feature);

      if (!feature || !firstSlide) {
        return;
      }

      setActive(feature, firstSlide);

      if (scrollboxIsScrollable()) {
        scrollbox.scrollTo({ top: 0, behavior: "smooth" });
      }
    });
  });

  triggers.forEach((trigger) => {
    trigger.addEventListener("click", () => {
      const feature = trigger.dataset.feature;
      const slide = trigger.dataset.slideTarget;

      if (!feature || !slide) {
        return;
      }

      setActive(feature, slide);
      scrollToSlide(feature, slide);
    });
  });

  scrollbox.addEventListener("scroll", requestSync, { passive: true });
  window.addEventListener("scroll", requestSync, { passive: true });
  window.addEventListener("resize", requestSync);

  root.dataset.discoverInitialized = "true";

  const initialFeature = root.dataset.activeFeature || tabs[0]?.dataset.featureTab;
  const initialSlide = root.dataset.activeSlide || getDefaultSlide(initialFeature);

  setActive(initialFeature, initialSlide);
  requestSync();
};

initDiscoverSection();
window.addEventListener("phx:page-loading-stop", initDiscoverSection);
