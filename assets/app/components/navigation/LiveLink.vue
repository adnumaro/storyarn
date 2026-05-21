<script setup lang="ts">
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
</script>

<template>
  <a v-bind="$attrs" :href="to" :data-phx-link="phxLink" :data-phx-link-state="phxLinkState">
    <slot />
  </a>
</template>
