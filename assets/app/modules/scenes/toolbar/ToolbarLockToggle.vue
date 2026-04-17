<script setup lang="ts">
import { Lock, Unlock } from "lucide-vue-next";

const { locked = false, disabled = false } = defineProps<{
  locked?: boolean;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  toggle: [];
}>();
</script>

<template>
  <button
    type="button"
    class="toolbar-btn"
    :class="{ 'text-red-500!': locked }"
    :disabled="disabled"
    :title="locked ? $t('scenes.lock_toggle.unlock') : $t('scenes.lock_toggle.lock')"
    @click="emit('toggle')"
  >
    <Lock v-if="locked" class="size-3.5" />
    <Unlock v-else class="size-3.5" />
  </button>
</template>
