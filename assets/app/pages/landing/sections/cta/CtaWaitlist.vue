<script setup>
import { useLiveVue } from "live_vue";
import { ArrowRight } from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { useRevealOnScroll } from "../../composables/useRevealOnScroll.js";

const props = defineProps({
  translations: { type: Object, required: true },
});

const { pushEvent } = useLiveVue();
const email = ref("");
const submitting = ref(false);

const { elementRef: sectionRef, isRevealed } = useRevealOnScroll();

async function handleSubmit() {
  if (!email.value || submitting.value) return;
  submitting.value = true;
  pushEvent("join_waitlist", { email: email.value });
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
            {{ translations.cta_title }}
          </h2>
          <p class="mb-2 max-w-160 leading-relaxed text-muted-foreground">
            {{ translations.cta_desc }}
          </p>
          <form class="mt-6 flex max-w-115 flex-wrap gap-3" @submit.prevent="handleSubmit">
            <Input
              v-model="email"
              type="email"
              :placeholder="translations.email_placeholder"
              required
              class="min-w-50 flex-1"
            />
            <Button type="submit" :disabled="submitting" class="gap-2">
              {{ translations.join_waitlist }}
              <ArrowRight class="size-4" />
            </Button>
          </form>
          <p class="mt-3 text-xs text-foreground/30">
            {{ translations.no_spam }}
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
