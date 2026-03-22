<script setup>
import { Check, Loader2 } from "lucide-vue-next";

const props = defineProps({
	status: { type: String, default: "idle" }, // "idle" | "saving" | "saved"
});
</script>

<template>
  <Transition
    enter-active-class="transition-opacity duration-200"
    leave-active-class="transition-opacity duration-200"
    enter-from-class="opacity-0"
    leave-to-class="opacity-0"
  >
    <span
      v-if="status !== 'idle'"
      class="inline-flex items-center gap-1.5 text-xs text-muted-foreground"
    >
      <Loader2 v-if="status === 'saving'" class="size-3 animate-spin" />
      <Check v-if="status === 'saved'" class="size-3 text-green-500" />
      <span>{{ status === "saving" ? "Saving..." : "Saved" }}</span>
    </span>
  </Transition>
</template>
