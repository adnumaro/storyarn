<script setup lang="ts">
import { Check, Clock3, LoaderCircle, Sparkles, TriangleAlert } from "@lucide/vue";
import { computed, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Textarea } from "@components/ui/textarea";
import type { PlaceholderIssue, SaveState } from "../../../domain/types";

/**
 * The translation itself: textarea, save state, placeholder check and the
 * machine-translation shortcut. ⌘↵ saves, ⇧⌘↵ saves and moves on.
 */
const {
  targetName,
  canEdit = false,
  hasProvider = false,
  saveState,
  placeholderIssue = null,
  placeholderCount = 0,
  translating = false,
} = defineProps<{
  targetName: string;
  canEdit?: boolean;
  hasProvider?: boolean;
  saveState: SaveState;
  placeholderIssue?: PlaceholderIssue | null;
  placeholderCount?: number;
  translating?: boolean;
}>();

const emit = defineEmits<{ save: []; "save-next": []; translate: [] }>();

const translatedText = defineModel<string>({ required: true });

const { t } = useI18n();

const wordCount = computed(() => {
  const trimmed = translatedText.value.trim();
  return trimmed === "" ? 0 : trimmed.split(/\s+/).length;
});

const saveIcons: Record<SaveState, Component | null> = {
  idle: null,
  dirty: Clock3,
  saving: LoaderCircle,
  saved: Check,
  error: TriangleAlert,
  conflict: TriangleAlert,
};

const saveIconClass: Record<SaveState, string> = {
  idle: "",
  dirty: "text-amber-500",
  saving: "animate-spin text-primary",
  saved: "text-primary",
  error: "text-destructive",
  conflict: "text-destructive",
};

interface PlaceholderStatus {
  text: string;
  tone: "muted" | "warning";
}

// Both diagnostics at once: a translation can miss one placeholder and add
// another, and the translator must fix both before the string can be saved.
function placeholderWarnings(): string[] {
  if (!placeholderIssue) return [];
  const warnings: string[] = [];
  if (placeholderIssue.missing.length) {
    warnings.push(
      t("localization.editor.placeholder_status_missing", {
        missing: placeholderIssue.missing.join(" "),
        matched: placeholderCount - placeholderIssue.missing.length,
        total: placeholderCount,
      }),
    );
  }
  if (placeholderIssue.extra.length) {
    warnings.push(
      t("localization.editor.placeholder_status_extra", {
        extra: placeholderIssue.extra.join(" "),
      }),
    );
  }
  return warnings;
}

const placeholderStatus = computed<PlaceholderStatus>(() => {
  const warnings = placeholderWarnings();
  if (warnings.length > 0) return { text: warnings.join(" · "), tone: "warning" };
  if (placeholderCount === 0) {
    return { text: t("localization.editor.placeholder_status_none"), tone: "muted" };
  }
  if (wordCount.value === 0) {
    return {
      text: t("localization.editor.placeholder_status_required", placeholderCount),
      tone: "muted",
    };
  }
  return { text: t("localization.editor.placeholder_status_ok"), tone: "muted" };
});

function onKeydown(event: KeyboardEvent): void {
  if (!(event.metaKey || event.ctrlKey) || event.key !== "Enter") return;
  event.preventDefault();
  if (event.shiftKey) emit("save-next");
  else emit("save");
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      class="flex items-center justify-between text-[11px] tracking-[0.06em] text-muted-foreground uppercase"
    >
      <label for="localization-translation-editor">
        {{ $t("localization.editor.translation", { target: targetName }) }}
      </label>
      <span
        class="inline-flex items-center gap-1.5 text-xs tracking-normal normal-case"
        aria-live="polite"
        data-testid="localization-save-state"
      >
        <component
          :is="saveIcons[saveState]"
          v-if="saveIcons[saveState]"
          :class="['size-[13px]', saveIconClass[saveState]]"
        />
        {{ $t(`localization.editor.save_${saveState}`) }}
      </span>
    </div>

    <div
      class="flex flex-col overflow-hidden rounded-md border border-input bg-background focus-within:border-ring focus-within:ring-[3px] focus-within:ring-ring/50"
    >
      <Textarea
        id="localization-translation-editor"
        v-model="translatedText"
        class="min-h-36 resize-y rounded-none border-0 bg-transparent px-4 py-3.5 text-[15px] leading-relaxed shadow-none focus-visible:ring-0 dark:bg-transparent"
        :disabled="!canEdit"
        :placeholder="$t('localization.editor.translation_placeholder', { target: targetName })"
        @keydown="onKeydown"
      />
      <div
        class="flex items-center gap-3 border-t border-border/60 py-2 pr-2 pl-3.5 text-xs text-muted-foreground"
      >
        <span class="tabular-nums">{{ $t("localization.editor.words", wordCount) }}</span>
        <span
          :class="[
            'inline-flex items-center gap-1.5',
            placeholderStatus.tone === 'warning' && 'text-orange-600 dark:text-orange-400',
          ]"
          data-testid="localization-placeholder-status"
        >
          <TriangleAlert
            v-if="placeholderStatus.tone === 'warning'"
            class="size-3"
            aria-hidden="true"
          />
          <Check v-else class="size-3" aria-hidden="true" />
          {{ placeholderStatus.text }}
        </span>
        <span class="flex-1" />
        <Button
          v-if="canEdit && hasProvider"
          variant="ghost"
          size="xs"
          :disabled="translating || saveState === 'saving'"
          @click="emit('translate')"
        >
          <LoaderCircle v-if="translating" class="size-3.5 animate-spin" />
          <Sparkles v-else class="size-3.5" />
          {{ $t("localization.editor.translate_deepl") }}
        </Button>
      </div>
    </div>
  </div>
</template>
