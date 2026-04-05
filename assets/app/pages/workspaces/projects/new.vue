<script setup>
import { useLiveForm } from "live_vue";
import { computed, ref, watch } from "vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import { Textarea } from "@components/ui/textarea/index.js";

const { form: formProp, title, submitLabel } = defineProps({
  form: { type: Object, required: true },
  title: { type: String, default: "New Project" },
  submitLabel: { type: String, default: "Create Project" },
});

const emit = defineEmits(["cancel"]);

const form = useLiveForm(() => formProp, {
  changeEvent: "validate_project",
  submitEvent: "create_project",
  debounceInMiliseconds: 300,
});

const name = form.field("name");
const description = form.field("description");

const touched = ref({ name: false, description: false });

const showNameError = computed(() => {
  return (touched.value.name || formProp.action === 'insert') && name.errorMessage.value;
});

const showDescriptionError = computed(() => {
  return (touched.value.description || formProp.action === 'insert') && description.errorMessage.value;
});

function updateField(field, val) {
  field.value = val;
  if (field.inputAttrs?.value?.onInput) {
    field.inputAttrs.value.onInput({ target: { value: val } });
  }
}
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-lg font-semibold">{{ title }}</h2>

    <div class="space-y-1.5">
      <Label for="project-name">Project Name</Label>
      <Input
        id="project-name"
        name="project[name]"
        :model-value="name.value"
        @update:model-value="v => updateField(name, v)"
        placeholder="My Narrative Project"
        required
        @blur="touched.name = true"
        :aria-invalid="showNameError ? 'true' : null"
      />
      <p
        v-if="showNameError"
        class="text-sm text-destructive flex items-center gap-1 mt-1"
      >
        {{ name.errorMessage.value }}
      </p>
    </div>

    <div class="space-y-1.5">
      <Label for="project-description">Description</Label>
      <Textarea
        id="project-description"
        name="project[description]"
        :model-value="description.value"
        @update:model-value="v => updateField(description, v)"
        placeholder="A brief description of your project"
        :rows="4"
        @blur="touched.description = true"
        :aria-invalid="showDescriptionError ? 'true' : null"
      />
      <p
        v-if="showDescriptionError"
        class="text-sm text-destructive flex items-center gap-1 mt-1"
      >
        {{ description.errorMessage.value }}
      </p>
    </div>

    <div class="flex justify-end gap-2 pt-2">
      <Button
        type="button"
        variant="ghost"
        @click="$emit('cancel')"
      >
        Cancel
      </Button>
      <Button @click="form.submit()" :disabled="!form.isValid.value">
        {{ submitLabel }}
      </Button>
    </div>
  </div>
</template>
