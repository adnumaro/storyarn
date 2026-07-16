<script setup lang="ts">
import { onMounted, onUnmounted } from "vue";
import {
  ArrowRight,
  Boxes,
  Bug,
  Check,
  CircleDot,
  GitBranch,
  Languages,
  Map,
  PackageCheck,
  Table2,
} from "lucide-vue-next";
import LiveLink from "@components/navigation/LiveLink.vue";
import CtaSignup from "@modules/public/landing/sections/cta/CtaSignup.vue";
import { consumeHistoryScroll } from "@app/shared/navigation/historyScroll";

defineProps<{
  isLoggedIn?: boolean;
  registrationUrl: string;
}>();

const workflowSteps = ["define", "write", "explore", "export"] as const;
const initialScrollPosition = consumeHistoryScroll();
let restoreScrollFrame: number | undefined;

const pillars = [
  {
    id: "sheets",
    icon: Table2,
    image: "/images/docs/sheets/sheets-character.webp",
    labelKey: "landing.discovery.features.sheets.label",
    titleKey: "landing.v2.pillars.sheets.title",
    descKey: "landing.v2.pillars.sheets.desc",
  },
  {
    id: "flows",
    icon: GitBranch,
    image: "/images/docs/flows/flows.webp",
    labelKey: "landing.discovery.features.flows.label",
    titleKey: "landing.v2.pillars.flows.title",
    descKey: "landing.v2.pillars.flows.desc",
  },
  {
    id: "localization",
    icon: Languages,
    image: "/images/docs/localization-dashboard.webp",
    labelKey: "landing.features.cards.localization.title",
    titleKey: "landing.v2.pillars.localization.title",
    descKey: "landing.v2.pillars.localization.desc",
  },
];

const operations = [
  { icon: Bug, titleKey: "landing.features.cards.debugging.title" },
  { icon: Map, titleKey: "landing.discovery.features.scenes.label" },
  { icon: PackageCheck, titleKey: "landing.features.cards.export.title" },
  { icon: Boxes, titleKey: "landing.v2.operations.source_truth" },
];

onMounted(() => {
  document.documentElement.classList.add("dark");
  document.documentElement.style.scrollBehavior = "smooth";

  // LiveView restores history scroll before this async Vue surface has its
  // full height. Restore once more after mount so browser scroll anchoring
  // cannot turn a small auth-page offset into a jump down the landing page.
  restoreScrollFrame = window.requestAnimationFrame(() => {
    document.documentElement.style.scrollBehavior = "auto";
    const hashTarget = window.location.hash
      ? document.getElementById(decodeURIComponent(window.location.hash.slice(1)))
      : null;

    if (hashTarget) hashTarget.scrollIntoView({ block: "start" });
    else window.scrollTo(0, initialScrollPosition);

    document.documentElement.style.scrollBehavior = "smooth";
  });
});

onUnmounted(() => {
  if (restoreScrollFrame !== undefined) window.cancelAnimationFrame(restoreScrollFrame);

  const stored = localStorage.getItem("phx:theme");
  const shouldBeDark = stored
    ? stored === "dark"
    : window.matchMedia("(prefers-color-scheme: dark)").matches;
  document.documentElement.classList.toggle("dark", shouldBeDark);
  document.documentElement.style.scrollBehavior = "";
});
</script>

<template>
  <div class="min-h-screen bg-background text-foreground">
    <section
      class="relative flex min-h-svh items-center overflow-hidden border-b border-border pt-28"
    >
      <img
        :src="'/images/landing/storyarn-lab-hero.webp'"
        alt=""
        class="absolute inset-0 h-full w-full object-cover object-center opacity-95"
        aria-hidden="true"
      />
      <div
        class="absolute inset-0 bg-linear-to-r from-background via-background/78 to-background/8"
        aria-hidden="true"
      ></div>
      <div class="absolute inset-0 bg-background/10" aria-hidden="true"></div>

      <div class="relative mx-auto w-[min(calc(100%-48px),1280px)] py-16">
        <div class="max-w-3xl">
          <div
            class="mb-5 inline-flex items-center gap-2 rounded-full border border-primary/25 bg-primary/10 px-3 py-1.5 text-xs font-semibold uppercase text-primary"
          >
            <CircleDot class="size-3" />
            {{ $t("landing.common.badge") }}
          </div>
          <h1 class="max-w-4xl text-5xl font-bold leading-none sm:text-6xl lg:text-7xl">
            {{ $t("landing.v2.hero.title") }}
          </h1>
          <p class="mt-6 max-w-2xl text-lg leading-8 text-foreground/78">
            {{ $t("landing.v2.hero.desc") }}
          </p>
          <div class="mt-8 flex flex-wrap gap-3">
            <LiveLink
              id="hero-registration-link"
              :to="registrationUrl"
              class="inline-flex h-11 items-center justify-center rounded-md bg-primary px-5 text-sm font-bold text-primary-foreground transition hover:bg-primary/90"
            >
              {{ $t("landing.v2.hero.primary_cta") }}
              <ArrowRight class="ml-2 size-4" />
            </LiveLink>
            <a
              href="#workflow"
              class="inline-flex h-11 items-center justify-center rounded-md border border-border bg-background/70 px-5 text-sm font-semibold text-foreground transition hover:bg-accent"
            >
              {{ $t("landing.hero.cta_workflow") }}
            </a>
          </div>
        </div>
      </div>
    </section>

    <section id="features-section" class="border-b border-border bg-background py-36">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="grid gap-8 lg:grid-cols-[0.8fr_1.2fr] lg:items-end">
          <div>
            <p class="text-sm font-semibold uppercase text-primary">
              {{ $t("landing.common.links.features") }}
            </p>
            <h2 class="mt-3 text-4xl font-bold leading-tight sm:text-5xl">
              {{ $t("landing.v2.features.title") }}
            </h2>
          </div>
          <p class="max-w-2xl text-lg leading-8 text-muted-foreground lg:justify-self-end">
            {{ $t("landing.v2.features.desc") }}
          </p>
        </div>

        <div class="mt-10 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          <div
            v-for="operation in operations"
            :key="operation.titleKey"
            class="rounded-lg border border-border bg-muted/35 p-5"
          >
            <component :is="operation.icon" class="size-5 text-primary" />
            <p class="mt-4 font-semibold">{{ $t(operation.titleKey) }}</p>
          </div>
        </div>
      </div>
    </section>

    <section id="discover" class="bg-muted/20 py-36">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="max-w-3xl">
          <p class="text-sm font-semibold uppercase text-primary">
            {{ $t("landing.common.links.discover") }}
          </p>
          <h2 class="mt-3 text-4xl font-bold leading-tight sm:text-5xl">
            {{ $t("landing.v2.discover.title") }}
          </h2>
          <p class="mt-5 text-lg leading-8 text-muted-foreground">
            {{ $t("landing.v2.discover.desc") }}
          </p>
        </div>

        <div class="mt-12 grid gap-24">
          <article
            v-for="(pillar, index) in pillars"
            :key="pillar.id"
            class="grid gap-8 lg:grid-cols-2 lg:items-center"
          >
            <div :class="[index % 2 === 1 && 'lg:order-2']">
              <div class="flex items-center gap-3 text-sm font-semibold uppercase text-primary">
                <component :is="pillar.icon" class="size-4" />
                {{ $t(pillar.labelKey) }}
              </div>
              <h3 class="mt-3 text-3xl font-bold leading-tight">
                {{ $t(pillar.titleKey) }}
              </h3>
              <p class="mt-4 max-w-xl leading-7 text-muted-foreground">
                {{ $t(pillar.descKey) }}
              </p>
            </div>
            <img
              :src="pillar.image"
              :alt="$t(pillar.titleKey)"
              class="aspect-16/10 w-full rounded-lg border border-border object-cover object-top shadow-xl"
            />
          </article>
        </div>
      </div>
    </section>

    <section id="workflow" class="border-y border-border bg-background py-36">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="max-w-3xl">
          <p class="text-sm font-semibold uppercase text-primary">
            {{ $t("landing.common.links.workflow") }}
          </p>
          <h2 class="mt-3 text-4xl font-bold leading-tight sm:text-5xl">
            {{ $t("landing.workflow.title") }}
          </h2>
          <p class="mt-5 text-lg leading-8 text-muted-foreground">
            {{ $t("landing.workflow.subtitle") }}
          </p>
        </div>

        <ol class="mt-12 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          <li
            v-for="(step, index) in workflowSteps"
            :key="step"
            class="rounded-lg border border-border bg-muted/30 p-5"
          >
            <div
              class="mb-5 flex size-8 items-center justify-center rounded-full bg-primary text-sm font-bold text-primary-foreground"
            >
              {{ index + 1 }}
            </div>
            <h3 class="text-lg font-bold">
              {{ $t(`landing.workflow.steps.${step}.title`) }}
            </h3>
            <p class="mt-3 leading-7 text-muted-foreground">
              {{ $t(`landing.workflow.steps.${step}.desc`) }}
            </p>
          </li>
        </ol>
      </div>
    </section>

    <section class="bg-muted/20 py-36">
      <div
        class="mx-auto grid w-[min(calc(100%-48px),1280px)] gap-8 lg:grid-cols-[0.9fr_1.1fr] lg:items-center"
      >
        <div>
          <p class="text-sm font-semibold uppercase text-primary">
            {{ $t("landing.v2.production.label") }}
          </p>
          <h2 class="mt-3 text-4xl font-bold leading-tight sm:text-5xl">
            {{ $t("landing.v2.production.title") }}
          </h2>
          <p class="mt-5 text-lg leading-8 text-muted-foreground">
            {{ $t("landing.v2.production.desc") }}
          </p>
          <ul class="mt-7 grid gap-3">
            <li
              v-for="item in $tm('landing.v2.production.items')"
              :key="$rt(item)"
              class="flex gap-3 leading-7 text-foreground/82"
            >
              <Check class="mt-1 size-5 flex-none text-primary" />
              <span>{{ $rt(item) }}</span>
            </li>
          </ul>
        </div>

        <img
          :src="'/images/docs/flows/flows-debug.webp'"
          :alt="$t('landing.v2.production.image_alt')"
          class="aspect-16/10 w-full rounded-lg border border-border object-cover object-top shadow-xl"
        />
      </div>
    </section>

    <CtaSignup :registration-url="registrationUrl" />
  </div>
</template>
