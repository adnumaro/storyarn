<script setup lang="ts">
import type { Component } from "lucide-vue-next";
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
} = defineProps<{
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  variant?: "default" | "destructive" | "warning";
  icon?: Component;
}>();

const open = defineModel<boolean>("open", { required: true });
const emit = defineEmits<{
  confirm: [];
  cancel: [];
}>();

const buttonVariant = variant === "warning" ? "outline" : variant;

function handleConfirm(): void {
  emit("confirm");
  open.value = false;
}

function handleCancel(): void {
  emit("cancel");
  open.value = false;
}
</script>

<template>
  <Dialog v-model:open="open">
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
      </DialogHeader>
      <DialogFooter>
        <Button variant="outline" size="sm" @click="handleCancel">
          {{ cancelText }}
        </Button>
        <Button :variant="buttonVariant" size="sm" @click="handleConfirm">
          {{ confirmText }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
