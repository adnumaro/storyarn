<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import { useLive } from "../../shared/composables/useLive";
import { useLiveEvent } from "@shared/composables/useLiveEvent";

const { actionLabels = {} } = defineProps<{
  actionLabels?: Record<string, string>;
}>();

interface CollabToastData {
  userColor: string;
  userEmail: string;
  action: string;
}

const live = useLive();
const toast = ref<CollabToastData | null>(null);
let hideTimeout: ReturnType<typeof setTimeout> | null = null;

onMounted(() => {
  useLiveEvent(
    "collab_toast",
    (data: Record<string, unknown>) => {
      toast.value = data as unknown as CollabToastData;
      if (hideTimeout) clearTimeout(hideTimeout);
      hideTimeout = setTimeout(() => {
        toast.value = null;
      }, 4000);
    },
    live,
  );
});

onUnmounted(() => {
  if (hideTimeout) clearTimeout(hideTimeout);
});
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
      <i18n-t keypath="common.collab_toast.message" tag="span" class="text-sm text-foreground">
        <template #name>
          <span class="font-medium">{{ toast.userEmail?.split("@")[0] }}</span>
        </template>
        <template #action>{{
          actionLabels[toast.action] || $t("common.collab_toast.made_a_change")
        }}</template>
      </i18n-t>
    </div>
  </Transition>
</template>
