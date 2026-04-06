<script setup>
import { BookmarkPlus, Loader2 } from "lucide-vue-next";
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

const { open, title, description, promoteVersion, loadingAction } = defineProps({
  open: { type: Boolean, required: true },
  title: { type: String, required: true },
  description: { type: String, required: true },
  promoteVersion: { type: Object, default: null },
  loadingAction: { type: String, default: null },
});

const emit = defineEmits(["update:open", "update:title", "update:description", "submit"]);
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>Name This Version</DialogTitle>
        <DialogDescription>Give this auto-save a name to make it a milestone.</DialogDescription>
      </DialogHeader>
      <form @submit.prevent="emit('submit')" class="space-y-4">
        <div class="space-y-2">
          <Label for="promote-title">Title</Label>
          <Input
            id="promote-title"
            :model-value="title"
            @update:model-value="emit('update:title', $event)"
            :placeholder="promoteVersion?.changeSummary || 'e.g., Before major refactor'"
            required
            autofocus
          />
        </div>
        <div class="space-y-2">
          <Label for="promote-description">Description (optional)</Label>
          <Textarea
            id="promote-description"
            :model-value="description"
            @update:model-value="emit('update:description', $event)"
            :rows="3"
            placeholder="Describe what this version captures..."
          />
        </div>
        <DialogFooter>
          <DialogClose as-child><Button variant="ghost" type="button">Cancel</Button></DialogClose>
          <Button type="submit" :disabled="!title.trim() || loadingAction === 'promote'">
            <Loader2 v-if="loadingAction === 'promote'" class="size-4 animate-spin mr-1" />
            <BookmarkPlus v-else class="size-4 mr-1" />
            Name Version
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
