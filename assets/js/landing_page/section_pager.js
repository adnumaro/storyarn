import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(ScrollTrigger);

const INTERACTIVE_IGNORE =
  "[data-feature-scrollbox], input, textarea, select, option, button, a[href], label";

function initLandingSectionPager() {
  const stack = document.getElementById("landing-sections-stack");
  const track = document.getElementById("landing-sections-track");
  const landingPage = document.querySelector(".landing-page");
  const heroFeaturesStack = document.getElementById("hero-features-stack");
  const footer = landingPage?.querySelector("footer");
  const sections = Array.from(track?.querySelectorAll("[data-section-step]") ?? []);

  if (!stack || !track || !landingPage || !heroFeaturesStack || sections.length === 0) {
    return;
  }

  if (landingPage.dataset.sectionPagerInitialized) return;
  landingPage.dataset.sectionPagerInitialized = "true";

  let resizeTimer = null;
  let animating = false;
  let currentIndex = 0;
  let pinTrigger = null;
  let intentObserver = null;

  function panelOffset(index) {
    return -(window.innerHeight * index);
  }

  function setPanelState(index) {
    currentIndex = index;
    gsap.set(track, { y: panelOffset(index) });
  }

  function releaseToNextSection() {
    intentObserver?.disable();
    requestAnimationFrame(() => {
      window.scrollTo(0, footer?.offsetTop ?? stack.offsetTop + window.innerHeight);
    });
  }

  function releaseToPrevSection() {
    intentObserver?.disable();
    requestAnimationFrame(() => {
      window.scrollTo(0, Math.max(heroFeaturesStack.offsetTop + 2, 0));
    });
  }

  function gotoPanel(index, isScrollingDown) {
    if (animating) return;
    animating = true;

    if ((index === sections.length && isScrollingDown) || (index === -1 && !isScrollingDown)) {
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

    gsap.to(track, {
      y: panelOffset(index),
      duration: 0.78,
      ease: "power3.inOut",
      overwrite: true,
      onComplete() {
        currentIndex = index;
        animating = false;
      },
      onInterrupt() {
        animating = false;
      },
    });
  }

  function buildPager() {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const shouldPage = !reduced && window.innerWidth > 640;

    if (!shouldPage) {
      landingPage.classList.remove("is-section-paged");
      gsap.set(track, { clearProps: "all" });
      return;
    }

    landingPage.classList.add("is-section-paged");
    setPanelState(0);

    intentObserver = ScrollTrigger.observe({
      type: "wheel,touch",
      onUp: () => !animating && gotoPanel(currentIndex + 1, true),
      onDown: () => !animating && gotoPanel(currentIndex - 1, false),
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
        setPanelState(0);
        intentObserver?.enable();
      },
      onEnterBack() {
        setPanelState(sections.length - 1);
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
    animating = false;
    intentObserver?.disable();
    intentObserver?.kill();
    intentObserver = null;
    pinTrigger?.kill();
    pinTrigger = null;
    landingPage.classList.remove("is-section-paged");
    gsap.killTweensOf(track);
    gsap.set(track, { clearProps: "all" });
  }

  function handleResize() {
    clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(() => {
      teardown();
      buildPager();
      ScrollTrigger.refresh();
    }, 160);
  }

  buildPager();
  window.addEventListener("resize", handleResize);

  window.addEventListener(
    "phx:page-loading-start",
    () => {
      window.removeEventListener("resize", handleResize);
      teardown();
      delete landingPage.dataset.sectionPagerInitialized;
    },
    { once: true },
  );
}

initLandingSectionPager();
window.addEventListener("phx:page-loading-stop", initLandingSectionPager);
