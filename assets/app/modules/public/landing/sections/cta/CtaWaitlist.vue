<script setup lang="ts">
import { useLiveVue } from "live_vue";
import { ArrowRight } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { useRevealOnScroll } from "../../composables/useRevealOnScroll";
import { capture } from "@/js/utils/posthog";

const live = useLiveVue();
const email = ref("");
const submitting = ref(false);

const { elementRef: sectionRef, isRevealed } = useRevealOnScroll();

async function handleSubmit() {
  if (!email.value || submitting.value) return;
  submitting.value = true;
  await live.pushEvent("join_waitlist", { email: email.value });
  capture("waitlist joined", {});
  email.value = "";
  submitting.value = false;
}
</script>

<template>
  <section
    id="waitlist"
    ref="sectionRef"
    class="scroll-mt-32 py-8 pb-24"
    :class="{ 'opacity-0 translate-y-7': !isRevealed, 'opacity-100 translate-y-0': isRevealed }"
    style="
      transition:
        opacity 1s cubic-bezier(0.22, 1, 0.36, 1),
        transform 1s cubic-bezier(0.22, 1, 0.36, 1);
    "
  >
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      <div
        class="lp-cta-band relative overflow-hidden rounded-4xl border border-border bg-muted/80 p-10"
      >
        <div class="relative z-10">
          <h2
            class="mb-3 text-[clamp(2rem,3vw,3.4rem)] font-bold leading-[0.96] tracking-[-0.06em] text-foreground"
          >
            {{ $t("landing.cta.title") }}
          </h2>
          <p class="mb-2 max-w-160 leading-relaxed text-muted-foreground">
            {{ $t("landing.cta.desc") }}
          </p>
          <form class="mt-6 flex max-w-xl flex-wrap gap-3" @submit.prevent="handleSubmit">
            <Input
              v-model="email"
              type="email"
              :placeholder="$t('landing.cta.placeholder')"
              required
              class="min-w-50 flex-1 border-border/40 bg-zinc-950/40 h-12 px-4 rounded-lg text-[15px]"
            />
            <Button
              type="submit"
              :disabled="submitting"
              class="gap-2 font-bold text-teal-950 hover:scale-105 transition-all border-0 h-12 px-6! rounded-lg text-[15px]"
              style="
                background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210));
                box-shadow:
                  0 0 20px rgba(34, 211, 238, 0.4),
                  inset 0 1px 0 rgba(255, 255, 255, 0.3);
              "
            >
              {{ $t("landing.cta.btn") }}
              <ArrowRight class="size-4" />
            </Button>
          </form>
          <p class="mt-3 text-xs text-foreground/40">
            {{ $t("landing.cta.footer") }}
          </p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.lp-cta-band::after {
  content: "";
  position: absolute;
  width: 22rem;
  height: 22rem;
  right: -6rem;
  bottom: -10rem;
  border-radius: 50%;
  background: hsl(var(--primary) / 0.14);
  filter: blur(80px);
}
</style>
