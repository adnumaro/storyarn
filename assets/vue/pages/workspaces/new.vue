<script setup>
import { useLiveForm } from "live_vue";
import { Button } from "@/vue/components/ui/button/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import { Label } from "@/vue/components/ui/label/index.js";
import { Textarea } from "@/vue/components/ui/textarea/index.js";

const props = defineProps({
	form: { type: Object, required: true },
	cancelUrl: { type: String, default: "/workspaces" },
});

const form = useLiveForm(() => props.form, {
	submitEvent: "save",
	debounceInMiliseconds: 300,
});

const name = form.field("name");
const description = form.field("description");
</script>

<template>
  <div class="max-w-lg mx-auto py-8 space-y-6">
    <div>
      <h1 class="text-2xl font-bold tracking-tight">Create a new workspace</h1>
      <p class="text-sm text-muted-foreground mt-1">
        Workspaces help you organize projects for different teams or purposes.
      </p>
    </div>

    <div class="space-y-4">
      <div class="space-y-1.5">
        <Label for="workspace-name">Workspace name</Label>
        <Input
          id="workspace-name"
          v-bind="name.inputAttrs.value"
          placeholder="My Workspace"
          required
        />
        <p v-if="name.errorMessage.value" class="text-sm text-destructive mt-1">
          {{ name.errorMessage.value }}
        </p>
      </div>

      <div class="space-y-1.5">
        <Label for="workspace-description">Description</Label>
        <Textarea
          id="workspace-description"
          v-bind="description.inputAttrs.value"
          placeholder="What is this workspace for?"
          :rows="3"
        />
        <p v-if="description.errorMessage.value" class="text-sm text-destructive mt-1">
          {{ description.errorMessage.value }}
        </p>
      </div>

      <div class="flex justify-end gap-2 pt-4">
        <a
          :href="cancelUrl"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="inline-flex items-center justify-center h-9 px-4 text-sm rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
        >
          Cancel
        </a>
        <Button @click="form.submit()">
          Create Workspace
        </Button>
      </div>
    </div>
  </div>
</template>
