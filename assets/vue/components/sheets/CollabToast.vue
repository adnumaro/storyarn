<script setup>
import { ref, onMounted, onUnmounted } from "vue";
import { useLive } from "@/vue/composables/useLive";

const live = useLive();
const toast = ref(null);
let hideTimeout = null;

const actionLabels = {
	block_created: "added a block",
	block_updated: "edited a block",
	block_deleted: "removed a block",
	block_reordered: "reordered blocks",
	block_type_changed: "changed a block type",
	sheet_updated: "updated the sheet",
	sheet_restored: "restored a version",
};

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
      <div
        class="size-2 rounded-full shrink-0"
        :style="{ backgroundColor: toast.userColor }"
      />
      <span class="text-sm text-foreground">
        <span class="font-medium">{{ toast.userEmail?.split("@")[0] }}</span>
        {{ actionLabels[toast.action] || "made a change" }}
      </span>
    </div>
  </Transition>
</template>
