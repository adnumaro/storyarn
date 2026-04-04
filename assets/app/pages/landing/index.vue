<script setup>
import { onMounted, onUnmounted } from "vue";
import CtaWaitlist from "./sections/cta/CtaWaitlist.vue";
import LandingFooter from "./sections/cta/Footer.vue";
import DiscoverSection from "./sections/discovery/DiscoverSection.vue";
import FeatureGrid from "./sections/FeatureGrid.vue";
import HeroSection from "./sections/hero/HeroSection.vue";

const { isLoggedIn } = defineProps({
  isLoggedIn: { type: Boolean, default: false },
});

// Import and initialize our GSAP scroll hijacker
import { useSectionScroll } from "./composables/useSectionScroll";
const { gotoPanel } = useSectionScroll();

// Force dark mode + smooth scroll on the landing page
function handleForceScroll(e) {
  if (e.detail && e.detail.panelIndex !== undefined) {
    const isDown = e.detail.isScrollingDown !== undefined ? e.detail.isScrollingDown : e.detail.panelIndex > 0;
    gotoPanel(e.detail.panelIndex, isDown, e.detail.tabIndex);
  }
}

onMounted(() => {
  document.documentElement.classList.add("dark");
  document.documentElement.style.scrollBehavior = "smooth";
  window.addEventListener("storyarn:force-scroll", handleForceScroll);
});

onUnmounted(() => {
  document.documentElement.classList.remove("dark");
  document.documentElement.style.scrollBehavior = "";
  window.removeEventListener("storyarn:force-scroll", handleForceScroll);
});
</script>

<template>
  <div class="landing-page">
    <div id="hero-features-stack" class="lp-hero-features-stack">
      <div id="features" class="lp-features-anchor" aria-hidden="true"></div>

      <div id="hero-features-stage" class="lp-hero-features-stage">
        <HeroSection />
        <FeatureGrid />
        
        <!-- Use data-section-step to denote scroll hijacker logic for these trailing panels -->
        <DiscoverSection data-section-step />
        
        <div class="lp-auto-section lp-cta-footer-section" data-section-step>
          <CtaWaitlist />
          <LandingFooter />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.lp-hero-features-stack.is-scroll-staged {
  min-height: 100svh;
}

.lp-hero-features-stack.is-scroll-staged .lp-hero-features-stage {
  position: relative;
  height: 100svh;
  overflow: clip;
}

.lp-hero-features-stack.is-scroll-staged :deep(#features-section) {
  position: absolute;
  inset: 0;
}

.lp-hero-features-stack.is-scroll-staged :deep([data-section-step]) {
  position: absolute;
  inset: 0;
  width: 100%;
  min-height: 100svh;
  background: 
    radial-gradient(circle at 50% -15%, rgb(0 0 0 / 28%), transparent 24%),
    linear-gradient(180deg, hsl(var(--background)) 0%, hsl(var(--background)) 54%, hsl(var(--background)) 100%);
}

.lp-hero-features-stack.is-scroll-staged :deep(.lp-cta-footer-section) {
  display: flex !important;
  flex-direction: column;
  justify-content: center;
}

.lp-hero-features-stack.is-scroll-staged :deep(.landing-footer) {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
}
</style>
