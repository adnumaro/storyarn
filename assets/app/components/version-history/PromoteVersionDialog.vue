<script setup lang="ts">
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

interface PromoteVersionEntry {
  versionNumber: number;
  changeSummary?: string;
}

const {
  open,
  title,
  description,
  promoteVersion = null,
  loadingAction = null,
} = defineProps<{
  open: boolean;
  title: string;
  description: string;
  promoteVersion?: PromoteVersionEntry | null;
  loadingAction?: string | null;
}>();

const emit = defineEmits<{
  "update:open": [open: boolean];
  "update:title": [title: string];
  "update:description": [description: string];
  submit: [];
}>();
</script>

<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>{{ $t("common.promote_version_dialog.title") }}</DialogTitle>
        <DialogDescription>{{ $t("common.promote_version_dialog.description") }}</DialogDescription>
      </DialogHeader>
      <form @submit.prevent="emit('submit')" class="space-y-4">
        <div class="space-y-2">
          <Label for="promote-title">{{ $t("common.promote_version_dialog.title_label") }}</Label>
          <Input
            id="promote-title"
            :model-value="title"
            @update:model-value="emit('update:title', String($event))"
            :placeholder="promoteVersion?.changeSummary || $t('common.promote_version_dialog.title_placeholder')"
            required
            autofocus
          />
        </div>
        <div class="space-y-2">
          <Label for="promote-description">{{ $t("common.promote_version_dialog.description_label") }}</Label>
          <Textarea
            id="promote-description"
            :model-value="description"
            @update:model-value="emit('update:description', String($event))"
            :rows="3"
            :placeholder="$t('common.promote_version_dialog.description_placeholder')"
          />
        </div>
        <DialogFooter>
          <DialogClose as-child><Button variant="ghost" type="button">{{ $t("common.cancel") }}</Button></DialogClose>
          <Button type="submit" :disabled="!title.trim() || loadingAction === 'promote'">
            <Loader2 v-if="loadingAction === 'promote'" class="size-4 animate-spin mr-1" />
            <BookmarkPlus v-else class="size-4 mr-1" />
            {{ $t("common.promote_version_dialog.submit") }}
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
