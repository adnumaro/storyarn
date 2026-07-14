<script setup lang="ts">
import { ArrowRight, Check } from "lucide-vue-next";
import LiveLink from "@components/navigation/LiveLink.vue";
import { useRevealOnScroll } from "../../composables/useRevealOnScroll";

defineProps<{
  registrationUrl: string;
}>();

const { elementRef: sectionRef, isRevealed } = useRevealOnScroll();
</script>

<template>
  <section
    id="signup"
    ref="sectionRef"
    class="scroll-mt-32 py-36"
    :class="{ 'translate-y-7 opacity-0': !isRevealed, 'translate-y-0 opacity-100': isRevealed }"
    style="
      transition:
        opacity 1s cubic-bezier(0.22, 1, 0.36, 1),
        transform 1s cubic-bezier(0.22, 1, 0.36, 1);
    "
  >
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      <div
        class="lp-cta-band relative overflow-hidden rounded-4xl border border-primary/20 bg-muted/80 p-8 sm:p-10 lg:p-12"
      >
        <div class="relative z-10 grid gap-8 lg:grid-cols-[1fr_auto] lg:items-end">
          <div>
            <p class="mb-4 text-xs font-bold uppercase tracking-[0.18em] text-primary">
              {{ $t("landing.cta.eyebrow") }}
            </p>
            <h2
              class="max-w-3xl text-[clamp(2rem,3vw,3.4rem)] font-bold leading-[0.96] tracking-[-0.06em] text-foreground"
            >
              {{ $t("landing.cta.title") }}
            </h2>
            <p class="mt-5 max-w-2xl leading-relaxed text-muted-foreground">
              {{ $t("landing.cta.desc") }}
            </p>
            <p class="mt-5 flex items-center gap-2 text-sm text-foreground/65">
              <Check class="size-4 text-primary" />
              {{ $t("landing.cta.footer") }}
            </p>
          </div>

          <LiveLink
            id="cta-registration-link"
            :to="registrationUrl"
            class="inline-flex h-12 shrink-0 items-center justify-center gap-2 rounded-lg px-6 text-[15px] font-bold text-teal-950 transition-all hover:scale-105"
            style="
              background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210));
              box-shadow:
                0 0 20px rgba(34, 211, 238, 0.4),
                inset 0 1px 0 rgba(255, 255, 255, 0.3);
            "
          >
            {{ $t("landing.cta.btn") }}
            <ArrowRight class="size-4" />
          </LiveLink>
        </div>
      </div>
    </div>
  </section>
</template>
