<script setup lang="ts">
import { useLiveForm, type Form } from "live_vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Textarea } from "@components/ui/textarea/index.ts";

interface WorkspaceFormValues {
  name: string;
  description: string;
}

const { form: formProp, cancelUrl = "/workspaces" } = defineProps<{
  form: Form<WorkspaceFormValues>;
  cancelUrl?: string;
}>();

const form = useLiveForm(() => formProp, {
  submitEvent: "save",
  debounceInMiliseconds: 300,
});

const name = form.field("name");
const description = form.field("description");
</script>

<template>
  <div class="max-w-lg mx-auto py-8 space-y-6">
    <div>
      <h1 class="text-2xl font-bold tracking-tight">{{ $t("workspace.new_workspace.title") }}</h1>
      <p class="text-sm text-muted-foreground mt-1">
        {{ $t("workspace.new_workspace.subtitle") }}
      </p>
    </div>

    <div class="space-y-4">
      <div class="space-y-1.5">
        <Label for="workspace-name">{{ $t("workspace.new_workspace.name") }}</Label>
        <Input
          v-bind="name.inputAttrs.value"
          id="workspace-name"
          :placeholder="$t('workspace.new_workspace.name_placeholder')"
          required
        />
        <p v-if="name.errorMessage.value" class="text-sm text-destructive mt-1">
          {{ name.errorMessage.value }}
        </p>
      </div>

      <div class="space-y-1.5">
        <Label for="workspace-description">{{ $t("workspace.new_workspace.description") }}</Label>
        <Textarea
          v-bind="description.inputAttrs.value"
          id="workspace-description"
          :placeholder="$t('workspace.new_workspace.description_placeholder')"
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
          {{ $t("workspace.new_workspace.cancel") }}
        </a>
        <Button @click="form.submit()">{{ $t("workspace.new_workspace.submit") }}</Button>
      </div>
    </div>
  </div>
</template>
