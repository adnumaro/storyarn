<script setup lang="ts">
import { computed } from "vue";
import { Avatar, AvatarFallback } from "@components/ui/avatar";

const {
  email = "",
  displayName = "",
  size = "sm",
  color = null,
} = defineProps<{
  email?: string;
  displayName?: string;
  size?: "xs" | "sm" | "md" | "lg";
  color?: string | null;
}>();

const initials = computed(() => {
  const name = displayName || email || "";
  if (!name) return "?";
  const parts = name.split(/[\s@.]+/).filter(Boolean);
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return name.slice(0, 2).toUpperCase();
});

const sizeClass = computed(() => {
  switch (size) {
    case "xs":
      return "size-5 text-[8px]";
    case "sm":
      return "size-7 text-[10px]";
    case "md":
      return "size-8 text-sm";
    case "lg":
      return "size-11 text-base";
    default:
      return "size-7 text-xs";
  }
});

const ringStyle = computed(() => {
  if (!color) return {};
  return { boxShadow: `0 0 0 1px ${color}` };
});
</script>

<template>
  <Avatar :class="sizeClass" :style="ringStyle">
    <AvatarFallback class="font-medium">
      {{ initials }}
    </AvatarFallback>
  </Avatar>
</template>
