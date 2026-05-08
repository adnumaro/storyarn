import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { onMounted, onUnmounted } from "vue";

// Enable ScrollTrigger
if (typeof window !== "undefined") {
  gsap.registerPlugin(ScrollTrigger);
}

const INTERACTIVE_IGNORE = "input, textarea, select, option, button, a[href], label";

function panelYPercent(panelIdx: number, activeIndex: number): number {
  if (panelIdx === activeIndex) return 0;
  return panelIdx < activeIndex ? -100 : 100;
}

interface SectionScrollReturn {
  gotoPanel: (index: number, isScrollingDown?: boolean, forcedTabIndex?: number) => void;
}

export function useSectionScroll(): SectionScrollReturn {
  let resizeTimer: ReturnType<typeof setTimeout> | null = null;
  let animating = false;
  let currentIndex = 0;
  let pinTrigger: ScrollTrigger | null = null;
  let intentObserver: Observer | null = null;
  let scrollCooldown: ReturnType<typeof setTimeout> | null = null;

  const DISCOVER_PANEL = 2;
  const DISCOVER_TOTAL_STEPS = 3;
  let discoverSubIndex = 0;
  let discoverBoundaryReady = false;
  let discoverBoundaryLock: ReturnType<typeof setTimeout> | null = null;
  let discoverStepTimer: ReturnType<typeof setTimeout> | null = null;

  let totalPanels = 3;

  function gotoDiscoverStep(stepIndex: number): void {
    if (stepIndex < 0 || stepIndex >= DISCOVER_TOTAL_STEPS) return;
    animating = true;
    discoverSubIndex = stepIndex;

    // Dispatch event so DiscoverSection.vue updates its tabs
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("storyarn:discover-step", { detail: discoverSubIndex }));
    }

    clearTimeout(discoverStepTimer!);
    discoverStepTimer = setTimeout(() => {
      animating = false;
      discoverStepTimer = null;
      scrollCooldown = setTimeout(() => {
        scrollCooldown = null;
      }, 400);
    }, 400);
  }

  function handleScrollDown(): void {
    if (animating || scrollCooldown) return;

    if (currentIndex === DISCOVER_PANEL) {
      if (discoverSubIndex < DISCOVER_TOTAL_STEPS - 1) {
        discoverBoundaryReady = false;
        clearTimeout(discoverBoundaryLock!);
        discoverBoundaryLock = null;
        gotoDiscoverStep(discoverSubIndex + 1);
        return;
      }
      if (!discoverBoundaryReady) {
        if (!discoverBoundaryLock) {
          discoverBoundaryLock = setTimeout(() => {
            discoverBoundaryReady = true;
            discoverBoundaryLock = null;
          }, 400);
        }
        return;
      }
      discoverBoundaryReady = false;
    }

    gotoPanel(currentIndex + 1, true);
  }

  function handleScrollUp(): void {
    if (animating || scrollCooldown) return;

    if (currentIndex === DISCOVER_PANEL) {
      if (discoverSubIndex > 0) {
        discoverBoundaryReady = false;
        clearTimeout(discoverBoundaryLock!);
        discoverBoundaryLock = null;
        gotoDiscoverStep(discoverSubIndex - 1);
        return;
      }
      if (!discoverBoundaryReady) {
        if (!discoverBoundaryLock) {
          discoverBoundaryLock = setTimeout(() => {
            discoverBoundaryReady = true;
            discoverBoundaryLock = null;
          }, 400);
        }
        return;
      }
      discoverBoundaryReady = false;
    }

    gotoPanel(currentIndex - 1, false);
  }

  function releaseToPrevSection(): void {
    const stack = document.getElementById("hero-features-stack");
    if (!stack) return;
    intentObserver?.disable();
    requestAnimationFrame(() => {
      window.scrollTo(0, Math.max(stack.offsetTop - 2, 0));
    });
  }

  /* eslint-disable complexity */
  function setPanel(index: number, animate = false): void {
    currentIndex = index;
    const heroContentInner = document.getElementById("hero-content-inner");
    const featuresSection = document.getElementById("features-section");
    const featureShell = document.querySelector("[data-feature-stage-shell]");
    const featureIntro = document.querySelector("[data-feature-intro]");
    const autoSections = gsap.utils.toArray<HTMLElement>("[data-section-step]");

    if (!featuresSection || !heroContentInner) return;

    if (!animate) {
      if (index === 0) {
        gsap.set(featuresSection, { yPercent: 100, y: 0, opacity: 1 });
        gsap.set(heroContentInner, { y: 0, opacity: 1 });
        if (featureShell) gsap.set(featureShell, { y: 72, opacity: 0.18 });
        if (featureIntro) gsap.set(featureIntro, { y: 28, opacity: 0.36 });
      } else if (index === 1) {
        gsap.set(featuresSection, { yPercent: 0, y: 0, opacity: 1 });
        gsap.set(heroContentInner, { y: -132, opacity: 0 });
        if (featureShell) gsap.set(featureShell, { y: 0, opacity: 1 });
        if (featureIntro) gsap.set(featureIntro, { y: 0, opacity: 1 });
      } else {
        gsap.set(featuresSection, { yPercent: -100 });
        gsap.set(heroContentInner, { y: -132, opacity: 0 });
        if (featureShell) gsap.set(featureShell, { y: 0, opacity: 1 });
        if (featureIntro) gsap.set(featureIntro, { y: 0, opacity: 1 });
      }

      autoSections.forEach((section, i) => {
        const panelIdx = i + 2;
        if (panelIdx === index) {
          gsap.set(section, { yPercent: 0 });
        } else if (panelIdx < index) {
          gsap.set(section, { yPercent: -100 });
        } else {
          gsap.set(section, { yPercent: 100 });
        }
      });
    }
  }

  /* eslint-disable complexity */
  function gotoPanel(index: number, isScrollingDown?: boolean, forcedTabIndex?: number): void {
    if (animating) return;
    animating = true;

    // Wait until elements are collected to count totalPanels
    const autoSections = gsap.utils.toArray<HTMLElement>("[data-section-step]");
    totalPanels = 2 + autoSections.length;

    if (index >= totalPanels && isScrollingDown) {
      animating = false;
      return;
    }
    if (index < 0 && !isScrollingDown) {
      gsap.delayedCall(0, () => {
        animating = false;
        releaseToPrevSection();
      });
      return;
    }

    const timeline = gsap.timeline({
      defaults: { duration: 0.76, ease: "power3.inOut" },
      onComplete() {
        currentIndex = index;
        animating = false;
        scrollCooldown = setTimeout(() => {
          scrollCooldown = null;
        }, 400);

        if (index === DISCOVER_PANEL) {
          if (forcedTabIndex !== undefined) {
            discoverSubIndex = forcedTabIndex;
          } else if (isScrollingDown) {
            discoverSubIndex = 0;
          } else {
            discoverSubIndex = DISCOVER_TOTAL_STEPS - 1;
          }
          if (typeof window !== "undefined") {
            window.dispatchEvent(
              new CustomEvent("storyarn:discover-step", { detail: discoverSubIndex }),
            );
          }
        }
      },
    });

    const from = currentIndex;
    const heroContentInner = document.getElementById("hero-content-inner");
    const featuresSection = document.getElementById("features-section");
    const featureShell = document.querySelector("[data-feature-stage-shell]");
    const featureIntro = document.querySelector("[data-feature-intro]");

    // Dynamic Universal State Solver for Arbitrary Navigation Jumps
    const isNavigationJump = isScrollingDown === undefined && Math.abs(from - index) > 1;

    let trgFeatY = -100;
    if (index === 0) trgFeatY = 100;
    else if (index === 1) trgFeatY = 0;
    const trgHeroY = index === 0 ? 0 : -132;
    const trgHeroOp = index === 0 ? 1 : 0;
    const trgShellY = index === 0 ? 72 : 0;
    const trgShellOp = index === 0 ? 0.18 : 1;
    const trgIntroY = index === 0 ? 28 : 0;
    const trgIntroOp = index === 0 ? 0.36 : 1;

    if (isNavigationJump) {
      const stage = document.getElementById("hero-features-stage");
      if (stage) {
        timeline
          .to(stage, { opacity: 0, duration: 0.3, ease: "power2.inOut" })
          .add(() => {
            gsap.set(featuresSection, { yPercent: trgFeatY });
            gsap.set(heroContentInner, { y: trgHeroY, opacity: trgHeroOp });
            if (featureShell) gsap.set(featureShell, { y: trgShellY, opacity: trgShellOp });
            if (featureIntro) gsap.set(featureIntro, { y: trgIntroY, opacity: trgIntroOp });
            autoSections.forEach((section, i) => {
              const panelIdx = i + 2;
              gsap.set(section, {
                yPercent: panelYPercent(panelIdx, index),
              });
            });
          })
          .to(stage, { opacity: 1, duration: 0.4, ease: "power2.inOut", clearProps: "opacity" });
        return;
      }
    }

    timeline
      .to(featuresSection, { yPercent: trgFeatY, duration: 0.8, ease: "power2.inOut" }, 0)
      .to(
        heroContentInner,
        { y: trgHeroY, opacity: trgHeroOp, duration: 0.8, ease: "power2.inOut" },
        0,
      );

    if (featureShell)
      timeline.to(
        featureShell,
        { y: trgShellY, opacity: trgShellOp, duration: 0.8, ease: "power2.out" },
        0,
      );
    if (featureIntro)
      timeline.to(
        featureIntro,
        { y: trgIntroY, opacity: trgIntroOp, duration: 0.8, ease: "power2.out" },
        0,
      );

    autoSections.forEach((section, i) => {
      const panelIdx = i + 2;
      let trgAutoY = 100;
      if (panelIdx === index) trgAutoY = 0;
      else if (panelIdx < index) trgAutoY = -100;

      if (panelIdx !== from && panelIdx !== index) {
        gsap.set(section, { yPercent: panelIdx < index ? -100 : 100 });
      }

      timeline.to(section, { yPercent: trgAutoY, duration: 0.8, ease: "power2.inOut" }, 0);
    });
  }

  function buildStage(): void {
    const stack = document.getElementById("hero-features-stack");
    if (!stack) return;

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const shouldStage = !reduced && window.innerWidth > 640;

    if (!shouldStage) {
      stack.classList.remove("is-scroll-staged");
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
        if (ScrollTrigger.isTouch && !(self.event.target as Element).closest(INTERACTIVE_IGNORE)) {
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
        if (currentIndex !== 0) setPanel(0);
        intentObserver?.enable();
      },
      onEnterBack() {
        // Find total sections
        const autoSections = gsap.utils.toArray<HTMLElement>("[data-section-step]");
        totalPanels = 2 + autoSections.length;
        if (currentIndex !== totalPanels - 1) setPanel(totalPanels - 1);
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

  function teardown(): void {
    clearTimeout(resizeTimer!);
    clearTimeout(scrollCooldown!);
    animating = false;
    intentObserver?.disable();
    intentObserver?.kill();
    intentObserver = null;
    pinTrigger?.kill();
    pinTrigger = null;

    const stack = document.getElementById("hero-features-stack");
    if (stack) stack.classList.remove("is-scroll-staged");

    // Clear GSAP properties
    const elements = [
      document.getElementById("features-section"),
      document.getElementById("hero-content-inner"),
      document.querySelector("[data-feature-stage-shell]"),
      document.querySelector("[data-feature-intro]"),
      ...gsap.utils.toArray("[data-feature-card]"),
      ...gsap.utils.toArray("[data-section-step]"),
    ].filter(Boolean);

    gsap.killTweensOf(elements);
    gsap.set(elements, { clearProps: "all" });
  }

  function handleResize(): void {
    clearTimeout(resizeTimer!);
    resizeTimer = window.setTimeout(() => {
      teardown();
      buildStage();
      ScrollTrigger.refresh();
    }, 160);
  }

  onMounted(() => {
    // Wait a tick for DOM to be ready
    setTimeout(() => {
      buildStage();
      window.addEventListener("resize", handleResize);
    }, 50);
  });

  onUnmounted(() => {
    window.removeEventListener("resize", handleResize);
    teardown();
  });

  return {
    gotoPanel, // useful to manually trigger scroll down if a button is clicked
  };
}
