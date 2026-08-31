<script setup lang="ts">
import { Loader2 } from "@lucide/vue";
import type { Component } from "vue";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Button } from "@components/ui/button";

const {
  title,
  description,
  confirmText = "Confirm",
  cancelText = "Cancel",
  variant = "default",
  icon,
  pending = false,
  pendingText,
  closeOnConfirm = true,
  error,
} = defineProps<{
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  variant?: "default" | "destructive" | "warning";
  icon?: Component;
  pending?: boolean;
  pendingText?: string;
  closeOnConfirm?: boolean;
  error?: string;
}>();

const open = defineModel<boolean>("open", { required: true });
const emit = defineEmits<{
  confirm: [];
  cancel: [];
}>();

const buttonVariant = variant === "warning" ? "outline" : variant;

function handleConfirm(): void {
  if (pending) return;

  emit("confirm");

  if (closeOnConfirm) {
    open.value = false;
  }
}

function handleCancel(): void {
  if (pending) return;

  emit("cancel");
  open.value = false;
}

function handleOpenUpdate(nextOpen: boolean): void {
  if (!pending || nextOpen) {
    open.value = nextOpen;
  }
}
</script>

<template>
  <Dialog :open="open" @update:open="handleOpenUpdate">
    <DialogContent class="sm:max-w-sm">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <component
            :is="icon"
            v-if="icon"
            class="size-5 shrink-0"
            :class="{
              'text-destructive': variant === 'destructive',
              'text-warning': variant === 'warning',
            }"
          />
          {{ title }}
        </DialogTitle>
        <DialogDescription v-if="description">
          {{ description }}
        </DialogDescription>
        <p v-if="pending" class="sr-only" role="status" aria-live="polite" aria-atomic="true">
          {{ pendingText || confirmText }}
        </p>
        <p v-if="error" role="alert" class="text-sm text-destructive">
          {{ error }}
        </p>
      </DialogHeader>
      <DialogFooter :aria-busy="pending">
        <Button variant="outline" size="sm" :disabled="pending" @click="handleCancel">
          {{ cancelText }}
        </Button>
        <Button :variant="buttonVariant" size="sm" :disabled="pending" @click="handleConfirm">
          <Loader2 v-if="pending" class="size-4 animate-spin" aria-hidden="true" />
          {{ confirmText }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
