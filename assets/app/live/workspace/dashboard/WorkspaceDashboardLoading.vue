<script setup lang="ts">
// This component is a simple loading spinner shown briefly
// while the LiveView redirects to the default workspace.
</script>

<template>
  <div class="mx-auto w-full max-w-7xl space-y-6 pb-8" aria-busy="true">
    <div class="h-72 animate-pulse rounded-3xl border border-border/60 bg-card/70" />
    <div class="h-16 animate-pulse rounded-2xl border border-border/60 bg-card/70" />
    <div class="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
      <div
        v-for="index in 3"
        :key="index"
        class="h-48 animate-pulse rounded-2xl border border-border/60 bg-card/70"
      />
    </div>
  </div>
</template>
