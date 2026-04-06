<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Textarea } from "@components/ui/textarea/index.ts";

interface FlowFormValues {
  name: string;
  description: string;
}

const {
  form: formProp,
  title = "New Flow",
  submitLabel = "Create Flow",
  cancelUrl = null,
} = defineProps<{
  form: Form<FlowFormValues>;
  title?: string;
  submitLabel?: string;
  cancelUrl?: string | null;
}>();

const form = useLiveForm(() => formProp, {
  changeEvent: "validate",
  submitEvent: "save",
  debounceInMiliseconds: 300,
});

const name = form.field("name");
const description = form.field("description");
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-lg font-semibold">{{ title }}</h2>

    <div class="space-y-1.5">
      <Label for="flow-name">Name</Label>
      <Input v-bind="name.inputAttrs.value" id="flow-name" placeholder="Main Story" required />
      <p
        v-if="name.errorMessage.value"
        class="text-sm text-destructive flex items-center gap-1 mt-1"
      >
        {{ name.errorMessage.value }}
      </p>
    </div>

    <div class="space-y-1.5">
      <Label for="flow-description">Description</Label>
      <Textarea
        v-bind="description.inputAttrs.value"
        id="flow-description"
        placeholder="Describe the purpose of this flow..."
        :rows="3"
      />
      <p
        v-if="description.errorMessage.value"
        class="text-sm text-destructive flex items-center gap-1 mt-1"
      >
        {{ description.errorMessage.value }}
      </p>
    </div>

    <div class="flex justify-end gap-2 pt-2">
      <a
        v-if="cancelUrl"
        :href="cancelUrl"
        data-phx-link="patch"
        data-phx-link-state="push"
        class="inline-flex items-center justify-center h-9 px-4 text-sm rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
      >
        Cancel
      </a>
      <Button @click="form.submit()" :disabled="!form.isValid.value">
        {{ submitLabel }}
      </Button>
    </div>
  </div>
</template>
