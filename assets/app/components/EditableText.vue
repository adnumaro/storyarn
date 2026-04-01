<script setup>
import { nextTick, ref, watch } from "vue";

const { modelValue, placeholder, tag, inputClass, displayClass, disabled } = defineProps({
  modelValue: { type: String, default: "" },
  placeholder: { type: String, default: "Untitled" },
  tag: { type: String, default: "span" },
  inputClass: { type: String, default: "" },
  displayClass: { type: String, default: "" },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:modelValue", "save"]);

const editing = ref(false);
const inputEl = ref(null);
const localValue = ref(modelValue);

watch(
  () => modelValue,
  (v) => (localValue.value = v),
);

function startEdit() {
  if (disabled) return;
  editing.value = true;
  nextTick(() => {
    inputEl.value?.focus();
    inputEl.value?.select();
  });
}

function save() {
  editing.value = false;
  const trimmed = localValue.value.trim();
  if (trimmed !== modelValue) {
    emit("update:modelValue", trimmed);
    emit("save", trimmed);
  }
}

function onKeydown(e) {
  if (e.key === "Enter") {
    e.preventDefault();
    save();
  }
  if (e.key === "Escape") {
    localValue.value = modelValue;
    editing.value = false;
  }
}
</script>

<template>
  <input
    v-if="editing"
    ref="inputEl"
    v-model="localValue"
    :class="['bg-transparent outline-none border-b border-primary', inputClass]"
    :placeholder="placeholder"
    @blur="save"
    @keydown="onKeydown"
  />
  <component
    :is="tag"
    v-else
    :class="[
      'cursor-pointer hover:opacity-70 transition-opacity',
      !modelValue && 'opacity-50',
      disabled && 'cursor-default hover:opacity-100',
      displayClass,
    ]"
    @dblclick="startEdit"
  >
    {{ modelValue || placeholder }}
  </component>
</template>
