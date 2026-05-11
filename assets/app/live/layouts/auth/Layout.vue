<script setup lang="ts">
import LiveLink from "@components/navigation/LiveLink.vue";
</script>

<template>
  <div id="auth-layout-shell" class="min-h-screen flex flex-col">
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <LiveLink to="/" class="flex items-center gap-2">
          <img
            :src="'/images/logos/logo-black-48.png'"
            alt="Storyarn"
            class="w-8 h-8 dark:hidden"
          />
          <img
            :src="'/images/logos/logo-white-48.png'"
            alt="Storyarn"
            class="w-8 h-8 hidden dark:block"
          />
          <span class="text-xl brand-logotype">Storyarn</span>
        </LiveLink>
      </div>
    </header>

    <main class="flex-1 flex items-center justify-center px-4 py-12 sm:px-6 lg:px-8">
      <div class="w-full max-w-md space-y-6">
        <slot />
      </div>
    </main>
  </div>
</template>
