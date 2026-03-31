<script setup>
const props = defineProps({
  translations: { type: Object, required: true },
});

const year = new Date().getFullYear();
</script>

<template>
  <footer class="border-t border-border/30 pb-8 pt-10">
    <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
      <div class="flex flex-col gap-8 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <img
            :src="'/images/logos/logo-name-white.png'"
            alt="Storyarn"
            class="mb-3 h-8 w-auto opacity-60"
          />
          <p class="max-w-xs text-sm leading-relaxed text-muted-foreground">
            {{ translations.footer_tagline }}
          </p>
        </div>
        <nav class="flex flex-wrap gap-x-6 gap-y-2 text-sm text-muted-foreground">
          <a href="#features-section" class="transition-colors hover:text-foreground">
            {{ translations.features }}
          </a>
          <a href="#discover" class="transition-colors hover:text-foreground">
            {{ translations.discover }}
          </a>
          <a href="#workflow" class="transition-colors hover:text-foreground">
            {{ translations.workflow }}
          </a>
          <a href="/docs" class="transition-colors hover:text-foreground">
            {{ translations.docs }}
          </a>
          <a href="/contact" class="transition-colors hover:text-foreground">
            {{ translations.contact }}
          </a>
        </nav>
      </div>
      <div class="mt-8 flex flex-wrap items-center gap-3 border-t border-border/20 pt-6">
        <span
          class="rounded-full border border-border/30 bg-muted/20 px-3 py-1 text-xs font-medium text-muted-foreground backdrop-blur-sm"
        >
          {{ translations.private_beta_badge }}
        </span>
        <span
          class="rounded-full border border-border/30 bg-muted/20 px-3 py-1 text-xs font-medium text-muted-foreground backdrop-blur-sm"
        >
          {{ translations.realtime_collab }}
        </span>
        <span
          class="rounded-full border border-border/30 bg-muted/20 px-3 py-1 text-xs font-medium text-muted-foreground backdrop-blur-sm"
        >
          {{ translations.version_snapshots }}
        </span>
        <span class="ml-auto text-xs text-muted-foreground/50"> &copy; {{ year }} Storyarn </span>
      </div>
    </div>
  </footer>
</template>
