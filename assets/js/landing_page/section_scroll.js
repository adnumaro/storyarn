import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { getMonitorAPI } from "./discover_monitor.js";

gsap.registerPlugin(ScrollTrigger);

const INTERACTIVE_IGNORE = "input, textarea, select, option, button, a[href], label";

function initLandingSectionScroll() {
  const stack = document.getElementById("hero-features-stack");
  const featuresSection = document.getElementById("features-section");
  const heroContentInner = document.getElementById("hero-content-inner");
  const featureShell = stack?.querySelector("[data-feature-stage-shell]");
  const featureIntro = stack?.querySelector("[data-feature-intro]");
  const featureCards = stack?.querySelectorAll("[data-feature-card]");
  const autoSections = Array.from(stack?.querySelectorAll("[data-section-step]") ?? []);
  const footer = document.querySelector(".landing-shell footer");

  if (
    !stack ||
    !featuresSection ||
    !heroContentInner ||
    !featureShell ||
    !featureIntro ||
    !featureCards?.length
  ) {
    return;
  }

  if (stack.dataset.sectionScrollInitialized) return;
  stack.dataset.sectionScrollInitialized = "true";

  const cardList = Array.from(featureCards);

  // Panel map: 0 = hero, 1 = features, 2+ = auto-sections
  const DISCOVER_PANEL = 2;
  const totalPanels = 2 + autoSections.length;

  let resizeTimer = null;
  let animating = false;
  let currentIndex = 0;
  let pinTrigger = null;
  let intentObserver = null;

  // ── Discover sub-pager ──

  const discoverRoot = stack.querySelector("[data-feature-shell]");
  const discoverTabs = Array.from(discoverRoot?.querySelectorAll("button[data-feature-tab]") ?? []);
  const discoverSteps = Array.from(discoverRoot?.querySelectorAll("[data-slide]") ?? []);
  const discoverTexts = Array.from(discoverRoot?.querySelectorAll("[data-discover-text]") ?? []);

  // Build flat list of {feature, slide} in tab order
  const discoverFlatSteps = [];
  discoverTabs.forEach((tab) => {
    const feature = tab.dataset.featureTab;
    discoverSteps
      .filter((step) => step.dataset.featureStep === feature)
      .forEach((step) => {
        discoverFlatSteps.push({ feature, slide: step.dataset.slide });
      });
  });

  let discoverSubIndex = 0;
  let discoverDebounce = null;

  function setDiscoverActive(feature, _slide) {
    if (!discoverRoot) return;

    discoverRoot.dataset.activeFeature = feature;

    // Toggle tab indicators
    discoverTabs.forEach((tab) => {
      const active = tab.dataset.featureTab === feature;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });

    // Toggle text overlays
    discoverTexts.forEach((text) => {
      const active = text.dataset.featureTab === feature;
      text.classList.toggle("is-active", active);
    });
  }

  function gotoDiscoverStep(index) {
    if (index < 0 || index >= discoverFlatSteps.length) return false;

    discoverSubIndex = index;

    // Animate the 3D monitor
    const monitor = getMonitorAPI();
    monitor?.setSubStep(index);
    const { feature, slide } = discoverFlatSteps[index];
    setDiscoverActive(feature, slide);
    return true;
  }

  // Tab click handlers — drive both text overlays and monitor
  discoverTabs.forEach((tab, index) => {
    tab.addEventListener("click", () => {
      if (index < discoverFlatSteps.length) {
        gotoDiscoverStep(index);
      }
    });
  });

  // ── Unified scroll handler ──

  function handleScrollDown() {
    if (animating) return;

    // On discover panel: advance sub-steps first
    if (currentIndex === DISCOVER_PANEL && discoverFlatSteps.length > 1) {
      if (discoverSubIndex < discoverFlatSteps.length - 1) {
        // Debounce discover sub-steps to prevent rapid scrolling
        if (discoverDebounce) return;
        discoverDebounce = setTimeout(() => {
          discoverDebounce = null;
        }, 400);

        gotoDiscoverStep(discoverSubIndex + 1);
        return;
      }
      // Exhausted all discover steps — fall through to next section
    }

    gotoPanel(currentIndex + 1, true);
  }

  function handleScrollUp() {
    if (animating) return;

    // On discover panel: retreat sub-steps first
    if (currentIndex === DISCOVER_PANEL && discoverFlatSteps.length > 1) {
      if (discoverSubIndex > 0) {
        if (discoverDebounce) return;
        discoverDebounce = setTimeout(() => {
          discoverDebounce = null;
        }, 400);

        gotoDiscoverStep(discoverSubIndex - 1);
        return;
      }
      // At first discover step — fall through to previous section
    }

    gotoPanel(currentIndex - 1, false);
  }

  // ── State setters ──

  function setHeroElements() {
    gsap.set(featuresSection, { yPercent: 100, y: 0, opacity: 1 });
    gsap.set(heroContentInner, { y: 0, opacity: 1 });
    gsap.set(featureShell, { y: 72, opacity: 0.18 });
    gsap.set(featureIntro, { y: 28, opacity: 0.36 });
    gsap.set(cardList, { y: 48, opacity: 0.18 });
  }

  function setFeaturesElements() {
    gsap.set(featuresSection, { yPercent: 0, y: 0, opacity: 1 });
    gsap.set(heroContentInner, { y: -132, opacity: 0 });
    gsap.set(featureShell, { y: 0, opacity: 1 });
    gsap.set(featureIntro, { y: 0, opacity: 1 });
    gsap.set(cardList, { y: 0, opacity: 1 });
  }

  function setFeaturesExited() {
    gsap.set(featuresSection, { yPercent: -100 });
    gsap.set(heroContentInner, { y: -132, opacity: 0 });
    gsap.set(featureShell, { y: 0, opacity: 1 });
    gsap.set(featureIntro, { y: 0, opacity: 1 });
    gsap.set(cardList, { y: 0, opacity: 1 });
  }

  function setAutoSections(activeIdx) {
    autoSections.forEach((section, i) => {
      const panelIdx = i + 2;
      if (panelIdx === activeIdx) {
        gsap.set(section, { yPercent: 0 });
      } else if (panelIdx < activeIdx) {
        gsap.set(section, { yPercent: -100 });
      } else {
        gsap.set(section, { yPercent: 100 });
      }
    });
  }

  function setPanel(index) {
    currentIndex = index;

    if (index === 0) {
      setHeroElements();
    } else if (index === 1) {
      setFeaturesElements();
    } else {
      setFeaturesExited();
    }

    setAutoSections(index);

    // Reset discover sub-index when entering/leaving discover
    if (index === DISCOVER_PANEL && discoverFlatSteps.length > 0) {
      // Will be set properly by onEnterBack or gotoPanel logic
    } else {
      discoverSubIndex = 0;
      if (discoverFlatSteps.length > 0) {
        setDiscoverActive(discoverFlatSteps[0].feature, discoverFlatSteps[0].slide);
      }
    }
  }

  // ── Release at boundaries ──

  function releaseToNextSection() {
    intentObserver?.disable();
    requestAnimationFrame(() => {
      window.scrollTo(0, footer?.offsetTop ?? stack.offsetTop + window.innerHeight);
    });
  }

  function releaseToPrevSection() {
    intentObserver?.disable();
    requestAnimationFrame(() => {
      window.scrollTo(0, Math.max(stack.offsetTop - 2, 0));
    });
  }

  // ── Panel transitions ──

  function animateHeroToFeatures(timeline) {
    timeline
      .to(featuresSection, { yPercent: 0 }, 0)
      .to(heroContentInner, { y: -132, opacity: 0 }, 0)
      .to(featureShell, { y: 0, opacity: 1 }, 0.12)
      .to(featureIntro, { y: 0, opacity: 1 }, 0.16)
      .to(cardList, { y: 0, opacity: 1, stagger: 0.045 }, 0.2);
  }

  function animateFeaturesToHero(timeline) {
    timeline
      .to(cardList, { y: 48, opacity: 0.18, stagger: { each: 0.03, from: "end" } }, 0)
      .to(featureIntro, { y: 28, opacity: 0.36 }, 0.04)
      .to(featureShell, { y: 72, opacity: 0.18 }, 0.08)
      .to(heroContentInner, { y: 0, opacity: 1 }, 0.08)
      .to(featuresSection, { yPercent: 100 }, 0.08);
  }

  function animateFeaturesToAuto(timeline, next) {
    timeline
      .to(featuresSection, { yPercent: -100 }, 0)
      .fromTo(next, { yPercent: 100 }, { yPercent: 0 }, 0);
  }

  function animateAutoToFeatures(timeline, current) {
    timeline
      .to(current, { yPercent: 100 }, 0)
      .to(featuresSection, { yPercent: 0 }, 0);
  }

  function animateAutoToAuto(timeline, current, next, isDown) {
    if (isDown) {
      timeline
        .to(current, { yPercent: -100 }, 0)
        .fromTo(next, { yPercent: 100 }, { yPercent: 0 }, 0);
    } else {
      timeline
        .fromTo(next, { yPercent: -100 }, { yPercent: 0 }, 0)
        .to(current, { yPercent: 100 }, 0);
    }
  }

  function gotoPanel(index, isScrollingDown) {
    if (animating) return;
    animating = true;

    // Beyond boundaries — release
    if ((index >= totalPanels && isScrollingDown) || (index < 0 && !isScrollingDown)) {
      gsap.delayedCall(0, () => {
        animating = false;

        if (isScrollingDown) {
          releaseToNextSection();
        } else {
          releaseToPrevSection();
        }
      });
      return;
    }

    // Discover entrance animation — runs concurrently with slide
    const discoverEl = document.getElementById("discover");
    if (index === DISCOVER_PANEL) {
      requestAnimationFrame(() => discoverEl?.classList.add("is-entered"));
    } else if (currentIndex === DISCOVER_PANEL) {
      discoverEl?.classList.remove("is-entered");
    }

    const timeline = gsap.timeline({
      defaults: { duration: 0.76, ease: "power3.inOut" },
      onComplete() {
        currentIndex = index;
        animating = false;

        // Monitor lifecycle: resume when entering discover, pause when leaving
        const monitor = getMonitorAPI();
        if (index === DISCOVER_PANEL) {
          monitor?.resume();
          if (isScrollingDown) {
            discoverSubIndex = 0;
            setDiscoverActive(discoverFlatSteps[0].feature, discoverFlatSteps[0].slide);
            monitor?.setSubStep(0);
          } else {
            discoverSubIndex = discoverFlatSteps.length - 1;
            const last = discoverFlatSteps[discoverSubIndex];
            setDiscoverActive(last.feature, last.slide);
            monitor?.setSubStep(discoverSubIndex);
          }
        } else if (from === DISCOVER_PANEL) {
          monitor?.pause();
        }
      },
    });

    const from = currentIndex;

    // Hero ↔ Features (custom animation)
    if (from === 0 && index === 1) {
      animateHeroToFeatures(timeline);
    } else if (from === 1 && index === 0) {
      animateFeaturesToHero(timeline);
    }
    // Features → first auto-section
    else if (from === 1 && index === 2) {
      animateFeaturesToAuto(timeline, autoSections[0]);
    }
    // First auto-section → Features
    else if (from === 2 && index === 1) {
      animateAutoToFeatures(timeline, autoSections[0]);
    }
    // Auto-section ↔ Auto-section
    else {
      const currentSection = autoSections[from - 2];
      const nextSection = autoSections[index - 2];
      animateAutoToAuto(timeline, currentSection, nextSection, isScrollingDown);
    }
  }

  // ── Build / teardown ──

  function buildStage() {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const shouldStage = !reduced && window.innerWidth > 640;

    if (!shouldStage) {
      stack.classList.remove("is-scroll-staged");
      gsap.set([featuresSection, heroContentInner, featureShell, featureIntro, ...cardList], {
        clearProps: "all",
      });
      autoSections.forEach((s) => gsap.set(s, { clearProps: "all" }));
      return;
    }

    stack.classList.add("is-scroll-staged");
    setPanel(0);

    intentObserver = ScrollTrigger.observe({
      type: "wheel,touch",
      onUp: () => handleScrollDown(),
      onDown: () => handleScrollUp(),
      wheelSpeed: -1,
      tolerance: 8,
      preventDefault: true,
      ignore: INTERACTIVE_IGNORE,
      onPress(self) {
        if (ScrollTrigger.isTouch && !self.event.target.closest(INTERACTIVE_IGNORE)) {
          self.event.preventDefault();
        }
      },
    });
    intentObserver.disable();

    pinTrigger = ScrollTrigger.create({
      trigger: stack,
      pin: true,
      pinSpacing: false,
      start: "top top",
      end: "+=1",
      anticipatePin: 1,
      onEnter() {
        if (currentIndex !== 0) {
          setPanel(0);
        }
        intentObserver?.enable();
      },
      onEnterBack() {
        if (currentIndex !== totalPanels - 1) {
          setPanel(totalPanels - 1);
        }
        intentObserver?.enable();
      },
      onLeave() {
        intentObserver?.disable();
      },
      onLeaveBack() {
        intentObserver?.disable();
      },
    });
  }

  function teardown() {
    clearTimeout(resizeTimer);
    clearTimeout(discoverDebounce);
    discoverDebounce = null;
    animating = false;
    intentObserver?.disable();
    intentObserver?.kill();
    intentObserver = null;
    pinTrigger?.kill();
    pinTrigger = null;
    stack.classList.remove("is-scroll-staged");
    gsap.killTweensOf([featuresSection, heroContentInner, featureShell, featureIntro, ...cardList]);
    gsap.set([featuresSection, heroContentInner, featureShell, featureIntro, ...cardList], {
      clearProps: "all",
    });
    autoSections.forEach((s) => {
      gsap.killTweensOf(s);
      gsap.set(s, { clearProps: "all" });
    });
  }

  function handleResize() {
    clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(() => {
      teardown();
      buildStage();
      ScrollTrigger.refresh();
    }, 160);
  }

  buildStage();
  window.addEventListener("resize", handleResize);

  window.addEventListener(
    "phx:page-loading-start",
    () => {
      window.removeEventListener("resize", handleResize);
      teardown();
      delete stack.dataset.sectionScrollInitialized;
    },
    { once: true },
  );
}

initLandingSectionScroll();
window.addEventListener("phx:page-loading-stop", initLandingSectionScroll);
