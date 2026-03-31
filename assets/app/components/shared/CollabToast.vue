<script setup>
import { onMounted, onUnmounted, ref } from "vue";
import { useLive } from "@composables/useLive";

const props = defineProps({
  actionLabels: { type: Object, default: () => ({}) },
});

const live = useLive();
const toast = ref(null);
let hideTimeout = null;

onMounted(() => {
  live.handleEvent("collab_toast", (data) => {
    toast.value = data;
    clearTimeout(hideTimeout);
    hideTimeout = setTimeout(() => {
      toast.value = null;
    }, 4000);
  });
});

onUnmounted(() => clearTimeout(hideTimeout));

function label(action) {
  return props.actionLabels[action] || "made a change";
}
</script>

<template>
  <Transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="translate-y-2 opacity-0"
    enter-to-class="translate-y-0 opacity-100"
    leave-active-class="transition duration-150 ease-in"
    leave-from-class="translate-y-0 opacity-100"
    leave-to-class="translate-y-2 opacity-0"
  >
    <div
      v-if="toast"
      class="fixed bottom-4 right-4 z-50 flex items-center gap-2 bg-card border border-border rounded-lg px-3 py-2 shadow-lg"
    >
      <div class="size-2 rounded-full shrink-0" :style="{ backgroundColor: toast.userColor }" />
      <span class="text-sm text-foreground">
        <span class="font-medium">{{ toast.userEmail?.split("@")[0] }}</span>
        {{ " " }}{{ label(toast.action) }}
      </span>
    </div>
  </Transition>
</template>
