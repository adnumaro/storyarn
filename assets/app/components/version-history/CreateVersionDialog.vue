<script setup>
import { Loader2, Save } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import { Textarea } from "@components/ui/textarea";

const { open, title, description, loadingAction } = defineProps({
  open: { type: Boolean, required: true },
  title: { type: String, required: true },
  description: { type: String, required: true },
  loadingAction: { type: String, default: null },
});

const emit = defineEmits(["update:open", "update:title", "update:description", "submit"]);
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>Create Version</DialogTitle>
        <DialogDescription>Save the current state as a named version.</DialogDescription>
      </DialogHeader>
      <form @submit.prevent="emit('submit')" class="space-y-4">
        <div class="space-y-2">
          <Label for="version-title">Title</Label>
          <Input
            id="version-title"
            :model-value="title"
            @update:model-value="emit('update:title', $event)"
            placeholder="e.g., Before major refactor"
            required
            autofocus
          />
        </div>
        <div class="space-y-2">
          <Label for="version-description">Description (optional)</Label>
          <Textarea
            id="version-description"
            :model-value="description"
            @update:model-value="emit('update:description', $event)"
            :rows="3"
            placeholder="Describe what this version captures..."
          />
        </div>
        <DialogFooter>
          <DialogClose as-child><Button variant="ghost" type="button">Cancel</Button></DialogClose>
          <Button type="submit" :disabled="!title.trim() || loadingAction === 'create'">
            <Loader2 v-if="loadingAction === 'create'" class="size-4 animate-spin mr-1" />
            <Save v-else class="size-4 mr-1" />
            Create Version
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
