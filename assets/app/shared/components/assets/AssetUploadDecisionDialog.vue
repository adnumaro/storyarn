<script setup lang="ts">
import { computed } from "vue";
import { FileImage, Loader2 } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import type { AssetUploadDialogState } from "@shared/composables/useAssetDecisionUpload";

const {
  state = null,
  uploading = false,
  progress = 0,
  error = null,
} = defineProps<{
  state?: AssetUploadDialogState | null;
  uploading?: boolean;
  progress?: number;
  error?: string | null;
}>();

const emit = defineEmits<{
  confirm: [];
  cancel: [];
}>();

const open = computed(() => !!state);

const targetLabel = computed(() => {
  if (!state?.target) return null;
  return `${state.target.width}x${state.target.height}`;
});
</script>

<template>
  <Dialog :open="open" @update:open="(value) => !value && emit('cancel')">
    <DialogContent :show-close-button="false" class="w-[calc(100vw-2rem)] max-w-lg overflow-hidden">
      <DialogHeader class="min-w-0">
        <DialogTitle>{{ $t("common.assets.upload_decision.title") }}</DialogTitle>
        <DialogDescription class="break-words">
          {{ $t("common.assets.upload_decision.description") }}
        </DialogDescription>
      </DialogHeader>

      <div v-if="state" class="min-w-0 space-y-4">
        <div
          class="flex min-w-0 items-start gap-3 overflow-hidden rounded-md border border-border bg-muted/30 p-3"
        >
          <FileImage class="mt-0.5 size-5 shrink-0 text-muted-foreground" />
          <div class="min-w-0 flex-1">
            <p class="break-all text-sm font-medium leading-snug">{{ state.fileName }}</p>
            <p class="text-xs text-muted-foreground">{{ state.fileSize }}</p>
          </div>
        </div>

        <div class="space-y-2 break-words text-sm text-muted-foreground">
          <p v-if="state.sourceExists">
            {{ $t("common.assets.upload_decision.source_exists") }}
          </p>
          <p v-if="state.variantExists">
            {{ $t("common.assets.upload_decision.variant_exists") }}
          </p>
          <p v-else-if="state.requiresVariant && targetLabel">
            {{ $t("common.assets.upload_decision.variant_required", { size: targetLabel }) }}
          </p>
          <p v-else>
            {{ $t("common.assets.upload_decision.original_ready") }}
          </p>
        </div>

        <div v-if="uploading" class="space-y-2">
          <div class="h-1.5 rounded-full bg-muted overflow-hidden">
            <div class="h-full bg-primary transition-all" :style="{ width: `${progress}%` }" />
          </div>
          <p class="text-xs text-muted-foreground">
            {{ $t("common.assets.upload_decision.processing") }}
          </p>
        </div>

        <p v-if="error" class="break-words text-sm text-destructive">{{ error }}</p>
      </div>

      <DialogFooter class="min-w-0 flex-wrap">
        <Button
          variant="ghost"
          class="w-full sm:w-auto"
          :disabled="uploading"
          @click="emit('cancel')"
        >
          {{ $t("common.cancel") }}
        </Button>
        <Button class="w-full sm:w-auto" :disabled="uploading" @click="emit('confirm')">
          <Loader2 v-if="uploading" class="size-4 animate-spin" />
          {{ $t("common.assets.upload_decision.confirm") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
