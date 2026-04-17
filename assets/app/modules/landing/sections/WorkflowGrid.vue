<script setup lang="ts">
const stepKeys = ["define", "write", "explore", "export"] as const;
</script>

<template>
  <section class="lp-auto-section scroll-mt-32 py-16 lg:py-20">
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      <!-- Section header -->
      <div class="mb-8 grid max-w-4xl gap-4">
        <h2
          class="text-[clamp(2.2rem,3vw,3.8rem)] font-bold leading-[0.97] tracking-[-0.06em] text-foreground"
        >
          {{ $t("landing.workflow.title") }}
        </h2>
        <p class="max-w-xl text-base leading-relaxed text-muted-foreground">
          {{ $t("landing.workflow.subtitle") }}
        </p>
      </div>

      <!-- Stepper grid -->
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <article
          v-for="(key, i) in stepKeys"
          :key="key"
          class="relative rounded-3xl border border-border/40 bg-muted/60 px-5 pb-6 pt-16 backdrop-blur-md transition-colors hover:border-border/80 hover:bg-muted/80"
        >
          <span
            class="absolute left-5 top-5 text-3xl font-extrabold tracking-tight text-foreground/20"
          >
            {{ String(i + 1).padStart(2, "0") }}
          </span>
          <h3 class="mb-3 text-lg font-bold tracking-tight text-foreground">
            {{ $t(`landing.workflow.steps.${key}.title`) }}
          </h3>
          <p class="leading-relaxed text-muted-foreground">
            {{ $t(`landing.workflow.steps.${key}.desc`) }}
          </p>
        </article>
      </div>
    </div>
  </section>
</template>
