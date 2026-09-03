<script setup lang="ts">
import { TriangleAlert } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";

/**
 * Typed confirmation for the destructive actions of a danger zone: the user
 * must type the resource name before the destructive button enables.
 */
const {
  title,
  description,
  confirmationValue,
  confirmationLabel,
  confirmText,
  cancelText,
  confirmId = null,
} = defineProps<{
  title: string;
  description: string;
  confirmationValue: string;
  confirmationLabel: string;
  confirmText: string;
  cancelText: string;
  confirmId?: string | null;
}>();

const open = defineModel<boolean>("open", { required: true });
const emit = defineEmits<{ confirm: [] }>();

const typed = ref("");
const matches = computed(() => typed.value.trim() === confirmationValue.trim());

watch(open, (value) => {
  if (!value) typed.value = "";
});

function confirm(): void {
  if (!matches.value) return;
  open.value = false;
  emit("confirm");
}
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <div class="flex items-center gap-2">
          <TriangleAlert class="size-5 text-destructive" />
          <DialogTitle>{{ title }}</DialogTitle>
        </div>
        <DialogDescription>{{ description }}</DialogDescription>
      </DialogHeader>

      <form class="flex flex-col gap-2" @submit.prevent="confirm">
        <Label for="settings-delete-confirmation">{{ confirmationLabel }}</Label>
        <Input
          id="settings-delete-confirmation"
          v-model="typed"
          autocomplete="off"
          :placeholder="confirmationValue"
        />
      </form>

      <DialogFooter>
        <Button type="button" variant="outline" @click="open = false">{{ cancelText }}</Button>
        <Button
          :id="confirmId ?? undefined"
          type="button"
          variant="destructive"
          :disabled="!matches"
          @click="confirm"
        >
          {{ confirmText }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
