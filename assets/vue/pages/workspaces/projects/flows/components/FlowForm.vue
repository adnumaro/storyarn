<script setup>
import { useLiveForm } from "live_vue";
import { Button } from "@/vue/components/ui/button/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import { Label } from "@/vue/components/ui/label/index.js";
import { Textarea } from "@/vue/components/ui/textarea/index.js";

const props = defineProps({
	form: { type: Object, required: true },
	title: { type: String, default: "New Flow" },
	submitLabel: { type: String, default: "Create Flow" },
	cancelUrl: { type: String, default: null },
});

const form = useLiveForm(() => props.form, {
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
      <Input
        id="flow-name"
        v-bind="name.inputAttrs.value"
        placeholder="Main Story"
        required
      />
      <p v-if="name.errorMessage.value" class="text-sm text-destructive flex items-center gap-1 mt-1">
        {{ name.errorMessage.value }}
      </p>
    </div>

    <div class="space-y-1.5">
      <Label for="flow-description">Description</Label>
      <Textarea
        id="flow-description"
        v-bind="description.inputAttrs.value"
        placeholder="Describe the purpose of this flow..."
        :rows="3"
      />
      <p v-if="description.errorMessage.value" class="text-sm text-destructive flex items-center gap-1 mt-1">
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
