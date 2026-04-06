<script setup lang="ts">
import { ref } from "vue";
import type { Component } from "vue";
import {
  Table2,
  GitBranch,
  Map,
  LayoutDashboard,
  LineChart,
  Bug,
  GitCommit,
  Languages,
  Package,
} from "lucide-vue-next";

interface FeatureSubLink {
  nameKey: string;
  index: number;
  icon: Component;
}

interface Feature {
  icon: Component;
  titleKey: string;
  descKey: string;
  colorClassText: string;
  subLinks?: FeatureSubLink[];
}

const scrollContainer = ref<HTMLDivElement | null>(null);
const activeIndex = ref(0);

const features: Feature[] = [
  {
    icon: LayoutDashboard,
    titleKey: "landing.features.cards.core.title",
    descKey: "landing.features.cards.core.desc",
    colorClassText: "text-cyan-400",
    subLinks: [
      { nameKey: "landing.features.cards.core.sublinks.sheets", index: 0, icon: Table2 },
      { nameKey: "landing.features.cards.core.sublinks.flows", index: 1, icon: GitBranch },
      { nameKey: "landing.features.cards.core.sublinks.scenes", index: 2, icon: Map },
    ],
  },
  {
    icon: LineChart,
    titleKey: "landing.features.cards.analytics.title",
    descKey: "landing.features.cards.analytics.desc",
    colorClassText: "text-blue-400",
  },
  {
    icon: Bug,
    titleKey: "landing.features.cards.debugging.title",
    descKey: "landing.features.cards.debugging.desc",
    colorClassText: "text-emerald-400",
  },
  {
    icon: GitCommit,
    titleKey: "landing.features.cards.vcs.title",
    descKey: "landing.features.cards.vcs.desc",
    colorClassText: "text-purple-400",
  },
  {
    icon: Languages,
    titleKey: "landing.features.cards.localization.title",
    descKey: "landing.features.cards.localization.desc",
    colorClassText: "text-amber-500",
  },
  {
    icon: Package,
    titleKey: "landing.features.cards.export.title",
    descKey: "landing.features.cards.export.desc",
    colorClassText: "text-zinc-400",
  },
];

// GSAP Shield: High-Performance Wheel Throttle
let isAnimating = false;

function handleWheel(e: WheelEvent) {
  const delta = Math.sign(e.deltaY);

  // We are within bounds: shield the event from the global GSAP Observer
  e.stopPropagation();

  // If we are fading/locked, just eat the event
  if (isAnimating) return;

  // Velocity Threshold: Ignore weak inertia tail-ends (macOS) after unlock
  if (Math.abs(e.deltaY) < 40) return;

  if (delta > 0) {
    if (activeIndex.value === features.length - 1) {
      gotoGlobal(2); // Jump to Discover
    } else {
      activeIndex.value++;
    }
    isAnimating = true;
  } else if (delta < 0) {
    if (activeIndex.value === 0) {
      gotoGlobal(0); // Jump to Hero
    } else {
      activeIndex.value--;
    }
    isAnimating = true;
  }

  // Quick 300ms release allows rapid intentional multi-swipes
  setTimeout(() => {
    isAnimating = false;
  }, 300);
}

let touchStartY = 0;
function handleTouchStart(e: TouchEvent) {
  touchStartY = e.touches[0].clientY;
}
function handleTouchMove(e: TouchEvent) {
  if (!touchStartY) return;

  const touchY = e.touches[0].clientY;
  const deltaY = touchStartY - touchY;
  const delta = Math.sign(deltaY);

  e.stopPropagation();

  if (isAnimating) return;
  if (Math.abs(deltaY) < 30) return; // Touch intent threshold

  if (delta > 0) {
    if (activeIndex.value === features.length - 1) {
      gotoGlobal(2);
    } else {
      activeIndex.value++;
    }
    isAnimating = true;
    touchStartY = touchY;
  } else if (delta < 0) {
    if (activeIndex.value === 0) {
      gotoGlobal(0);
    } else {
      activeIndex.value--;
    }
    isAnimating = true;
    touchStartY = touchY;
  }

  setTimeout(() => {
    isAnimating = false;
  }, 300);
}

// Router trigger jumping over GSAP timeline safely
function gotoGlobal(panelIndex: number, tabIndex?: number) {
  if (typeof window !== "undefined") {
    const detail = { panelIndex, tabIndex };
    if (tabIndex !== undefined) detail.tabIndex = tabIndex;

    window.dispatchEvent(new CustomEvent("storyarn:force-scroll", { detail }));
  }
}
</script>

<template>
  <section
    id="features-section"
    class="relative z-20 flex flex-col h-svh bg-background"
    @wheel="handleWheel"
    @touchstart="handleTouchStart"
    @touchmove="handleTouchMove"
  >
    <!-- Global Fixed Header Area (Spanning 100% width) -->
    <div
      class="pt-28 lg:pt-48 px-8 lg:px-24 pb-12 lg:pb-24 relative z-30 w-full shrink-0 bg-background/80 backdrop-blur-xl border-b border-border/20 shadow-sm shadow-black/5 overflow-hidden"
    >
      <!-- Glow embedded securely inside the Header -->
      <div
        class="pointer-events-none absolute inset-x-0 -top-112.5 left-1/2 h-150 w-250 -translate-x-1/2 rounded-full bg-primary/10 blur-[160px]"
      ></div>

      <div class="max-w-7xl mx-auto relative z-10">
        <h2
          class="text-[clamp(2.5rem,4vw,4.5rem)] font-bold tracking-tight text-foreground leading-none mb-6 max-w-4xl"
        >
          {{ $t("landing.features.section_title") }}
        </h2>
        <p class="text-lg lg:text-xl leading-relaxed text-muted-foreground lg:mr-8 max-w-3xl">
          {{ $t("landing.features.section_subtitle") }}
        </p>
      </div>
    </div>

    <div class="relative z-20 flex flex-1 w-full max-w-7xl mx-auto flex-col lg:flex-row min-h-0">
      <!-- Visual Sticking Container (Top Mobile, Right Desktop) -->
      <div
        class="lg:w-[45%] w-full lg:h-full basis-[45%] lg:basis-auto shrink-0 bg-black/10 lg:order-2 flex items-center justify-center border-b lg:border-b-0 lg:border-l border-border/20 relative"
      >
        <transition name="vp-fade" mode="out-in">
          <div
            :key="activeIndex"
            class="flex items-center justify-center w-full max-w-70 lg:max-w-100 aspect-square rounded-3xl bg-muted/30 border border-border/20 backdrop-blur-md shadow-2xl"
          >
            <component
              :is="features[activeIndex].icon"
              class="w-32 h-32 lg:w-48 lg:h-48 opacity-20 transition-all duration-700 delay-100"
              :class="features[activeIndex].colorClassText"
            />
          </div>
        </transition>
      </div>

      <!-- Left Column Wrapper: ONLY contains the Scrollable Body now -->
      <div class="lg:w-[55%] w-full flex-1 flex flex-col lg:order-1 relative h-full">
        <!-- Dynamic Presenter Container (No Scroll) -->
        <div
          ref="scrollContainer"
          class="flex-1 w-full flex flex-col justify-center relative touch-pan-y"
        >
          <!-- Using the same smooth Crossfade mechanic as the Visual wrapper! -->
          <transition name="vp-fade" mode="out-in">
            <div
              :key="activeIndex"
              class="px-8 lg:px-24 w-full flex flex-col max-w-xl left-0 right-0 absolute lg:static my-auto"
            >
              <h3 class="mb-4 text-3xl lg:text-4xl font-bold tracking-tight text-foreground">
                {{ $t(features[activeIndex].titleKey) }}
              </h3>
              <p class="leading-relaxed text-lg lg:text-xl text-muted-foreground mb-8 text-pretty">
                {{ $t(features[activeIndex].descKey) }}
              </p>

              <!-- SubLinks para el Punto 1 (Dovetail style sub-feature cards) -->
              <div v-if="features[activeIndex].subLinks" class="flex flex-col gap-4 mt-8">
                <div
                  v-for="sublink in features[activeIndex].subLinks"
                  :key="sublink.nameKey"
                  @click="gotoGlobal(2, sublink.index)"
                  class="group flex items-center justify-between p-4 rounded-xl border border-border/40 bg-muted/20 hover:bg-muted/60 transition-colors cursor-pointer"
                >
                  <div class="flex items-center gap-4">
                    <component :is="sublink.icon" class="size-5 text-primary" />
                    <span class="font-semibold text-foreground">{{ $t(sublink.nameKey) }}</span>
                  </div>
                  <span
                    class="text-xl text-muted-foreground group-hover:translate-x-1 group-hover:text-primary transition-all duration-300"
                    >→</span
                  >
                </div>
              </div>
            </div>
          </transition>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
/* Crossfade animation mechanics for the fixed Visual Area */
.vp-fade-enter-active,
.vp-fade-leave-active {
  transition:
    opacity 0.5s cubic-bezier(0.4, 0, 0.2, 1),
    transform 0.5s cubic-bezier(0.4, 0, 0.2, 1);
}
.vp-fade-enter-from {
  opacity: 0;
  transform: scale(0.96) translateY(10px);
}
.vp-fade-leave-to {
  opacity: 0;
  transform: scale(1.04) translateY(-10px);
}

/* Optional custom scrollbar design for the content container overlaying beautifully */
::-webkit-scrollbar {
  width: 6px;
}
::-webkit-scrollbar-track {
  background: transparent;
}
::-webkit-scrollbar-thumb {
  background: hsl(var(--border));
  border-radius: 12px;
}
::-webkit-scrollbar-thumb:hover {
  background: hsl(var(--muted-foreground));
}
</style>
