<script setup>
import { Compass } from "lucide-vue-next";
import { useRevealOnScroll } from "../composables/useRevealOnScroll.js";

const { translations } = defineProps({
  translations: { type: Object, default: () => ({ exploration_items: [] }) },
});

const { elementRef: sectionRef, isRevealed } = useRevealOnScroll();
</script>

<template>
  <section class="relative py-24">
    <div
      ref="sectionRef"
      class="mx-auto w-[min(calc(100%-48px),1280px)]"
      :class="{ 'opacity-0 translate-y-7': !isRevealed, 'opacity-100 translate-y-0': isRevealed }"
      style="
        transition:
          opacity 1s cubic-bezier(0.22, 1, 0.36, 1),
          transform 1s cubic-bezier(0.22, 1, 0.36, 1);
      "
    >
      <div class="grid items-center gap-10 lg:grid-cols-[1.1fr_0.72fr]">
        <div>
          <div
            class="mb-4 inline-flex size-11 items-center justify-center rounded-xl bg-primary/10 text-primary"
          >
            <Compass class="size-5" />
          </div>
          <h2
            class="text-[clamp(2rem,3vw,3.4rem)] font-bold leading-[0.96] tracking-[-0.06em] text-foreground"
          >
            {{ translations.exploration_title }}
          </h2>
          <p class="mt-4 max-w-160 leading-relaxed text-muted-foreground">
            {{ translations.exploration_desc }}
          </p>
          <ul class="mt-6 space-y-3">
            <li
              v-for="(item, i) in translations.exploration_items"
              :key="i"
              class="relative pl-4 leading-relaxed text-foreground/70"
            >
              <span class="absolute left-0 top-[0.7em] size-2 rounded-full bg-primary" />
              {{ item }}
            </li>
          </ul>
        </div>
        <!-- Screenshot placeholder -->
        <div
          class="flex min-h-70 items-center justify-center rounded-2xl border-2 border-dashed border-border/40 bg-muted/10 text-sm text-muted-foreground"
        >
          1280 x 436 — Exploration screenshot
        </div>
      </div>
    </div>
  </section>
</template>
