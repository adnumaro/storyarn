import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { onMounted, onUnmounted } from "vue";

// Enable ScrollTrigger
if (typeof window !== "undefined") {
  gsap.registerPlugin(ScrollTrigger);
}

const INTERACTIVE_IGNORE = "input, textarea, select, option, button, a[href], label";

export function useSectionScroll() {
  let resizeTimer = null;
  let animating = false;
  let currentIndex = 0;
  let pinTrigger = null;
  let intentObserver = null;
  let scrollCooldown = null;

  const DISCOVER_PANEL = 2;
  const DISCOVER_TOTAL_STEPS = 3;
  let discoverSubIndex = 0;
  let discoverBoundaryReady = false;
  let discoverBoundaryLock = null;
  let discoverStepTimer = null;
  
  let totalPanels = 3; 

  function gotoDiscoverStep(stepIndex) {
    if (stepIndex < 0 || stepIndex >= DISCOVER_TOTAL_STEPS) return;
    animating = true;
    discoverSubIndex = stepIndex;

    // Dispatch event so DiscoverSection.vue updates its tabs
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("storyarn:discover-step", { detail: discoverSubIndex }));
    }

    clearTimeout(discoverStepTimer);
    discoverStepTimer = setTimeout(() => {
      animating = false;
      discoverStepTimer = null;
      scrollCooldown = setTimeout(() => { scrollCooldown = null; }, 400);
    }, 400);
  }

  function handleScrollDown() {
    if (animating || scrollCooldown) return;

    if (currentIndex === DISCOVER_PANEL) {
      if (discoverSubIndex < DISCOVER_TOTAL_STEPS - 1) {
        discoverBoundaryReady = false;
        clearTimeout(discoverBoundaryLock);
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

  function handleScrollUp() {
    if (animating || scrollCooldown) return;

    if (currentIndex === DISCOVER_PANEL) {
      if (discoverSubIndex > 0) {
        discoverBoundaryReady = false;
        clearTimeout(discoverBoundaryLock);
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

  function releaseToPrevSection() {
    const stack = document.getElementById("hero-features-stack");
    if (!stack) return;
    intentObserver?.disable();
    requestAnimationFrame(() => {
      window.scrollTo(0, Math.max(stack.offsetTop - 2, 0));
    });
  }

  /* eslint-disable complexity */
  function setPanel(index, animate = false) {
    currentIndex = index;
    const heroContentInner = document.getElementById("hero-content-inner");
    const featuresSection = document.getElementById("features-section");
    const featureShell = document.querySelector("[data-feature-stage-shell]");
    const featureIntro = document.querySelector("[data-feature-intro]");
    const cardList = gsap.utils.toArray("[data-feature-card]");
    const autoSections = gsap.utils.toArray("[data-section-step]");

    if (!featuresSection || !heroContentInner) return;

    if (!animate) {
      if (index === 0) {
        gsap.set(featuresSection, { yPercent: 100, y: 0, opacity: 1 });
        gsap.set(heroContentInner, { y: 0, opacity: 1 });
        if(featureShell) gsap.set(featureShell, { y: 72, opacity: 0.18 });
        if(featureIntro) gsap.set(featureIntro, { y: 28, opacity: 0.36 });
        if(cardList.length) gsap.set(cardList, { y: 48, opacity: 0.18 });
      } else if (index === 1) {
        gsap.set(featuresSection, { yPercent: 0, y: 0, opacity: 1 });
        gsap.set(heroContentInner, { y: -132, opacity: 0 });
        if(featureShell) gsap.set(featureShell, { y: 0, opacity: 1 });
        if(featureIntro) gsap.set(featureIntro, { y: 0, opacity: 1 });
        if(cardList.length) gsap.set(cardList, { y: 0, opacity: 1 });
      } else {
        gsap.set(featuresSection, { yPercent: -100 });
        gsap.set(heroContentInner, { y: -132, opacity: 0 });
        if(featureShell) gsap.set(featureShell, { y: 0, opacity: 1 });
        if(featureIntro) gsap.set(featureIntro, { y: 0, opacity: 1 });
        if(cardList.length) gsap.set(cardList, { y: 0, opacity: 1 });
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
  function gotoPanel(index, isScrollingDown) {
    if (animating) return;
    animating = true;

    // Wait until elements are collected to count totalPanels
    const autoSections = gsap.utils.toArray("[data-section-step]");
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
        scrollCooldown = setTimeout(() => { scrollCooldown = null; }, 400);

        if (index === DISCOVER_PANEL) {
          if (isScrollingDown) {
            discoverSubIndex = 0;
          } else {
            discoverSubIndex = DISCOVER_TOTAL_STEPS - 1;
          }
          if (typeof window !== "undefined") {
            window.dispatchEvent(new CustomEvent("storyarn:discover-step", { detail: discoverSubIndex }));
          }
        }
      },
    });

    const from = currentIndex;
    const heroContentInner = document.getElementById("hero-content-inner");
    const featuresSection = document.getElementById("features-section");
    const featureShell = document.querySelector("[data-feature-stage-shell]");
    const featureIntro = document.querySelector("[data-feature-intro]");
    const cardList = gsap.utils.toArray("[data-feature-card]");

    if (from === 0 && index === 1) {
      timeline
        .to(featuresSection, { yPercent: 0 }, 0)
        .to(heroContentInner, { y: -132, opacity: 0 }, 0)
        .to(featureShell, { y: 0, opacity: 1 }, 0.12)
        .to(featureIntro, { y: 0, opacity: 1 }, 0.16)
        .to(cardList, { y: 0, opacity: 1, stagger: 0.045 }, 0.2);
    } else if (from === 1 && index === 0) {
      timeline
        .to(cardList, { y: 48, opacity: 0.18, stagger: { each: 0.03, from: "end" } }, 0)
        .to(featureIntro, { y: 28, opacity: 0.36 }, 0.04)
        .to(featureShell, { y: 72, opacity: 0.18 }, 0.08)
        .to(heroContentInner, { y: 0, opacity: 1 }, 0.08)
        .to(featuresSection, { yPercent: 100 }, 0.08);
    } else if (from === 1 && index === 2) {
      timeline
        .to(featuresSection, { yPercent: -100 }, 0)
        .fromTo(autoSections[0], { yPercent: 100 }, { yPercent: 0 }, 0);
    } else if (from === 2 && index === 1) {
      timeline
        .to(autoSections[0], { yPercent: 100 }, 0)
        .to(featuresSection, { yPercent: 0 }, 0);
    } else {
      const currentSection = autoSections[from - 2];
      const nextSection = autoSections[index - 2];
      if (isScrollingDown) {
        timeline
          .to(currentSection, { yPercent: -100 }, 0)
          .fromTo(nextSection, { yPercent: 100 }, { yPercent: 0 }, 0);
      } else {
        timeline
          .fromTo(nextSection, { yPercent: -100 }, { yPercent: 0 }, 0)
          .to(currentSection, { yPercent: 100 }, 0);
      }
    }
  }

  function buildStage() {
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
        if (currentIndex !== 0) setPanel(0);
        intentObserver?.enable();
      },
      onEnterBack() {
        // Find total sections
        const autoSections = gsap.utils.toArray("[data-section-step]");
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

  function teardown() {
    clearTimeout(resizeTimer);
    clearTimeout(scrollCooldown);
    animating = false;
    intentObserver?.disable();
    intentObserver?.kill();
    intentObserver = null;
    pinTrigger?.kill();
    pinTrigger = null;
    
    const stack = document.getElementById("hero-features-stack");
    if(stack) stack.classList.remove("is-scroll-staged");

    // Clear GSAP properties
    const elements = [
      document.getElementById("features-section"),
      document.getElementById("hero-content-inner"),
      document.querySelector("[data-feature-stage-shell]"),
      document.querySelector("[data-feature-intro]"),
      ...gsap.utils.toArray("[data-feature-card]"),
      ...gsap.utils.toArray("[data-section-step]")
    ].filter(Boolean);

    gsap.killTweensOf(elements);
    gsap.set(elements, { clearProps: "all" });
  }

  function handleResize() {
    clearTimeout(resizeTimer);
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
    gotoPanel // useful to manually trigger scroll down if a button is clicked
  };
}
