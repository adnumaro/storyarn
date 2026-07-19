<script setup lang="ts">
import { ArrowUpRight } from "lucide-vue-next";
import type { Component } from "vue";

const {
  icon,
  label,
  value,
  href = null,
  linkMode = "redirect",
  testId = null,
} = defineProps<{
  icon: Component;
  label: string;
  value: number | string;
  href?: string | null;
  linkMode?: "patch" | "redirect";
  testId?: string | null;
}>();
</script>

<template>
  <component
    :is="href ? 'a' : 'div'"
    :href="href || undefined"
    :data-phx-link="href ? linkMode : undefined"
    :data-phx-link-state="href ? 'push' : undefined"
    :data-testid="testId || undefined"
    :class="[
      'group relative isolate min-h-32 overflow-hidden rounded-2xl border border-border/70 bg-card/85 p-4 shadow-[0_1px_2px_rgba(0,0,0,0.04)] backdrop-blur-sm transition-all duration-200',
      href
        ? 'hover:-translate-y-0.5 hover:border-primary/35 hover:shadow-[0_14px_36px_-22px_color-mix(in_oklch,var(--color-primary)_55%,transparent)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50'
        : 'cursor-default',
    ]"
  >
    <div
      aria-hidden="true"
      class="absolute inset-x-0 top-0 h-0.5 bg-linear-to-r from-primary via-primary/80 to-project-accent"
    />
    <div
      aria-hidden="true"
      class="absolute -right-8 -top-10 size-28 rounded-full bg-primary/[0.07] blur-2xl transition-transform duration-300 group-hover:scale-125"
    />

    <div class="relative flex h-full flex-col justify-between gap-4">
      <div class="flex items-start justify-between gap-3">
        <span
          class="grid size-9 place-items-center rounded-xl border border-primary/15 bg-primary/[0.09] text-primary shadow-sm"
        >
          <component :is="icon" class="size-4.5" aria-hidden="true" />
        </span>
        <ArrowUpRight
          v-if="href"
          class="size-4 text-muted-foreground/35 transition-all duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-primary"
          aria-hidden="true"
        />
      </div>

      <div>
        <p class="text-2xl font-bold tracking-tight text-foreground tabular-nums sm:text-3xl">
          {{ value }}
        </p>
        <p class="mt-1 truncate text-xs font-medium text-muted-foreground">
          {{ label }}
        </p>
      </div>
    </div>
  </component>
</template>
