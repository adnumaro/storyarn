<script setup lang="ts">
import { rememberCurrentHistoryScroll } from "@app/shared/navigation/historyScroll";

defineOptions({ inheritAttrs: false });

const {
  to,
  mode = "navigate",
  state = "push",
} = defineProps<{
  to: string;
  mode?: "navigate" | "patch" | "external";
  state?: "push" | "replace";
}>();

function resolvePhxLink(): "patch" | "redirect" | undefined {
  if (mode === "external") return undefined;
  if (mode === "patch") return "patch";
  return "redirect";
}

const phxLink = resolvePhxLink();
const phxLinkState = mode === "external" ? undefined : state;

function rememberScrollPosition(): void {
  if (mode !== "navigate" || state !== "push") return;

  // LiveView only copies a redirect's scroll position when it is truthy, so
  // leaving a page at scrollY 0 produces a history entry without `scroll`.
  // Persist it explicitly before LiveView's window-level click handler runs so
  // back navigation restores the exact source position, including the top.
  rememberCurrentHistoryScroll();
}
</script>

<template>
  <a
    v-bind="$attrs"
    :href="to"
    :data-phx-link="phxLink"
    :data-phx-link-state="phxLinkState"
    @click="rememberScrollPosition"
  >
    <slot />
  </a>
</template>
