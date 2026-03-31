<script setup>
import { Lock, Unlock } from "lucide-vue-next";

defineProps({
  locked: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["toggle"]);
</script>

<template>
  <button
    type="button"
    class="v2-toolbar-btn"
    :class="{ '!text-red-500': locked }"
    :disabled="disabled"
    :title="locked ? 'Unlock' : 'Lock'"
    @click="emit('toggle')"
  >
    <Lock v-if="locked" class="size-3.5" />
    <Unlock v-else class="size-3.5" />
  </button>
</template>
