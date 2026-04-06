<script setup lang="ts">
import { Crown, User } from "lucide-vue-next";
import { ToggleField } from "@components/form-fields";

const {
  isPlayable = false,
  isLeader = false,
  disabled = false,
} = defineProps<{
  isPlayable?: boolean;
  isLeader?: boolean;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  togglePlayable: [];
  toggleLeader: [];
}>();
</script>

<template>
  <div class="space-y-2">
    <ToggleField
      label="Playable character"
      :icon="User"
      :checked="isPlayable"
      :disabled="disabled"
      @toggle="emit('togglePlayable')"
    />
    <ToggleField
      v-if="isPlayable"
      label="Party leader"
      :icon="Crown"
      :checked="isLeader"
      :disabled="disabled"
      @toggle="emit('toggleLeader')"
    />
  </div>
</template>
