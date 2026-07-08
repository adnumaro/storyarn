<script setup lang="ts">
import type { HTMLAttributes } from "vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Eye, EyeOff } from "lucide-vue-next";
import { Input } from "@components/ui/input";
import { cn } from "@shared/utils/utils";

defineOptions({ inheritAttrs: false });

const {
  modelValue,
  defaultValue,
  class: className,
} = defineProps<{
  modelValue?: string | number;
  defaultValue?: string | number;
  class?: HTMLAttributes["class"];
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string | number];
}>();

const { t } = useI18n();
const visible = ref(false);
const inputRef = ref<InstanceType<typeof Input> | null>(null);

const inputType = computed(() => (visible.value ? "text" : "password"));
const visibilityLabel = computed(() =>
  visible.value ? t("auth.password_visibility.hide") : t("auth.password_visibility.show"),
);

function updateModel(value: string | number): void {
  emit("update:modelValue", value);
}

function toggleVisibility(): void {
  visible.value = !visible.value;
}

function focus(): void {
  inputRef.value?.focus();
}

defineExpose({ focus });
</script>

<template>
  <div class="relative">
    <Input
      ref="inputRef"
      v-bind="$attrs"
      :model-value="modelValue"
      :default-value="defaultValue"
      :type="inputType"
      :class="cn('pr-10', className)"
      @update:model-value="updateModel"
    />
    <button
      type="button"
      class="absolute inset-y-0 right-0 flex w-10 items-center justify-center rounded-r-md text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      :aria-label="visibilityLabel"
      :aria-pressed="visible"
      @click="toggleVisibility"
    >
      <Eye v-if="!visible" class="size-4" aria-hidden="true" />
      <EyeOff v-else class="size-4" aria-hidden="true" />
    </button>
  </div>
</template>
