<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { Monitor, Moon, Sun } from "lucide-vue-next";

type ThemePreference = "system" | "light" | "dark";
type ThemeSelectorSize = "default" | "xs";

const { labels, size = "default" } = defineProps<{
  labels: Record<ThemePreference, string>;
  size?: ThemeSelectorSize;
}>();

const currentTheme = ref<ThemePreference>("system");

const selectorClass = computed(() => [
  "card relative flex flex-row items-center rounded-full border-2 border-border bg-border",
  size === "xs" ? "h-8 w-24" : "h-9 w-[6.75rem]",
]);

const iconClass = computed(() => [
  size === "xs" ? "size-3.5" : "size-4",
  "opacity-75 hover:opacity-100",
]);

const themeKnobClass = computed(() => {
  if (currentTheme.value === "light") return "left-1/3";
  if (currentTheme.value === "dark") return "left-2/3";
  return "left-0";
});

function readTheme(): ThemePreference {
  const value = localStorage.getItem("phx:theme");
  if (value === "light" || value === "dark") return value;
  return "system";
}

function setTheme(theme: ThemePreference): void {
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
  } else {
    localStorage.setItem("phx:theme", theme);
  }

  currentTheme.value = theme;
  window.dispatchEvent(new CustomEvent("phx:set-theme"));
}

function syncTheme(): void {
  currentTheme.value = readTheme();
}

onMounted(() => {
  syncTheme();
  window.addEventListener("storage", syncTheme);
  window.addEventListener("phx:set-theme", syncTheme);
});

onUnmounted(() => {
  window.removeEventListener("storage", syncTheme);
  window.removeEventListener("phx:set-theme", syncTheme);
});
</script>

<template>
  <div :class="selectorClass">
    <div
      :class="[
        'absolute h-full w-1/3 rounded-full border border-border bg-background brightness-200 transition-[left]',
        themeKnobClass,
      ]"
    />
    <button
      type="button"
      class="relative flex h-full w-1/3 cursor-pointer items-center justify-center"
      :aria-label="labels.system"
      :title="labels.system"
      :aria-pressed="currentTheme === 'system'"
      @click="setTheme('system')"
    >
      <Monitor :class="iconClass" />
    </button>
    <button
      type="button"
      class="relative flex h-full w-1/3 cursor-pointer items-center justify-center"
      :aria-label="labels.light"
      :title="labels.light"
      :aria-pressed="currentTheme === 'light'"
      @click="setTheme('light')"
    >
      <Sun :class="iconClass" />
    </button>
    <button
      type="button"
      class="relative flex h-full w-1/3 cursor-pointer items-center justify-center"
      :aria-label="labels.dark"
      :title="labels.dark"
      :aria-pressed="currentTheme === 'dark'"
      @click="setTheme('dark')"
    >
      <Moon :class="iconClass" />
    </button>
  </div>
</template>
