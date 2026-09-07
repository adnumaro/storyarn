<script setup lang="ts">
import { X, History } from "@lucide/vue";
import Sidebar from "@shell/Sidebar.vue";
import { Button } from "@components/ui/button";
import IdeaEditor from "./IdeaEditor.vue";
import { useBoardText } from "../composables/useBoardText";
import type { Inspection, IdeaContent } from "../types";
defineProps<{ inspection: Inspection | null; loading: boolean; canEdit: boolean }>();
const emit = defineEmits<{
  close: [];
  more: [];
  moreConflicts: [];
  restore: [content: IdeaContent];
}>();
const { t } = useBoardText();
</script>
<template>
  <Sidebar side="right" open @close="emit('close')"
    ><template #header
      ><div class="flex items-center justify-between py-2.5">
        <span class="flex items-center gap-2 text-sm font-medium"
          ><History class="size-4" />{{ t("ideation.history") }}</span
        ><button
          type="button"
          class="toolbar-btn"
          :aria-label="t('ideation.close')"
          @click="emit('close')"
        >
          <X class="size-4" />
        </button></div
    ></template>
    <p v-if="loading && !inspection" class="p-3 text-sm text-muted-foreground" role="status">
      {{ t("ideation.loading") }}
    </p>
    <div v-if="inspection" class="space-y-4 py-2">
      <details
        v-if="inspection.conflicts.length || inspection.conflicts_next"
        class="rounded-lg border p-3"
      >
        <summary class="cursor-pointer text-xs font-medium">{{ t("ideation.conflicts") }}</summary>
        <div v-for="receipt in inspection.conflicts" :key="receipt.id" class="mt-3 border-t pt-3">
          <IdeaEditor :value="receipt.attempted.body" readonly :label="t('ideation.conflicts')" />
          <Button
            v-if="canEdit"
            size="sm"
            variant="ghost"
            @click="emit('restore', receipt.attempted)"
            >{{ t("ideation.useText") }}</Button
          >
        </div>
        <Button
          v-if="inspection.conflicts_next"
          size="sm"
          variant="ghost"
          :disabled="loading"
          @click="emit('moreConflicts')"
          >{{ t("ideation.moreHistory") }}</Button
        >
      </details>
      <details
        v-for="revision in inspection.history"
        :key="revision.number"
        class="rounded-lg border p-3"
      >
        <summary class="cursor-pointer text-xs font-medium">
          {{ t("ideation.revision", { number: revision.number }) }}
        </summary>
        <div class="mt-3">
          <IdeaEditor :value="revision.body" readonly :label="t('ideation.history')" />
        </div>
        <Button
          v-if="canEdit"
          variant="ghost"
          size="sm"
          class="mt-2"
          @click="emit('restore', revision)"
          >{{ t("ideation.useText") }}</Button
        >
      </details>
      <Button
        v-if="inspection.history_next"
        size="sm"
        variant="ghost"
        :disabled="loading"
        @click="emit('more')"
        >{{ t("ideation.moreHistory") }}</Button
      >
    </div>
  </Sidebar>
</template>
