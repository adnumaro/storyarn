<script setup lang="ts">
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

const {
  open,
  title,
  description,
  loadingAction = null,
} = defineProps<{
  open: boolean;
  title: string;
  description: string;
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
        <DialogTitle>{{ $t("common.create_version_dialog.title") }}</DialogTitle>
        <DialogDescription>{{ $t("common.create_version_dialog.description") }}</DialogDescription>
      </DialogHeader>
      <form @submit.prevent="emit('submit')" class="space-y-4">
        <div class="space-y-2">
          <Label for="version-title">{{ $t("common.create_version_dialog.title_label") }}</Label>
          <Input
            id="version-title"
            :model-value="title"
            @update:model-value="emit('update:title', String($event))"
            :placeholder="$t('common.create_version_dialog.title_placeholder')"
            required
            autofocus
          />
        </div>
        <div class="space-y-2">
          <Label for="version-description">{{
            $t("common.create_version_dialog.description_label")
          }}</Label>
          <Textarea
            id="version-description"
            :model-value="description"
            @update:model-value="emit('update:description', String($event))"
            :rows="3"
            :placeholder="$t('common.create_version_dialog.description_placeholder')"
          />
        </div>
        <DialogFooter>
          <DialogClose as-child
            ><Button variant="ghost" type="button">{{ $t("common.cancel") }}</Button></DialogClose
          >
          <Button type="submit" :disabled="!title.trim() || loadingAction === 'create'">
            <Loader2 v-if="loadingAction === 'create'" class="size-4 animate-spin mr-1" />
            <Save v-else class="size-4 mr-1" />
            {{ $t("common.create_version_dialog.title") }}
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
