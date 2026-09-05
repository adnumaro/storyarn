<script setup lang="ts">
import {
  ArrowRight,
  ChevronLeft,
  ChevronRight,
  ExternalLink,
  FileText,
  Lock,
  Workflow,
  X,
} from "@lucide/vue";
import { computed } from "vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Button } from "@components/ui/button";
import UserAvatar from "@components/UserAvatar.vue";
import type { SelectedText } from "../../domain/types";
import StatusBadge from "../status/StatusBadge.vue";
import TextFlag from "../status/TextFlag.vue";
import ConflictBanner from "./editor/ConflictBanner.vue";
import EditorMeta from "./editor/EditorMeta.vue";
import OutdatedBanner from "./editor/OutdatedBanner.vue";
import SourcePane from "./editor/SourcePane.vue";
import TranslationPane from "./editor/TranslationPane.vue";
import type { EditorNavigation, EditorState } from "./editor/types";

/**
 * The inline editor, read top-down: context › source › translation › meta.
 * State lives in `useTranslationEditor`; this component only renders it.
 */
const {
  text,
  sourceName,
  canEdit = false,
  hasProvider = false,
  navigation,
  editorState,
} = defineProps<{
  text: SelectedText;
  sourceName: string;
  canEdit?: boolean;
  hasProvider?: boolean;
  navigation: EditorNavigation;
  editorState: EditorState;
}>();

const emit = defineEmits<{
  save: [];
  "save-next": [];
  translate: [];
  "confirm-current": [];
  "retry-conflict": [];
  "reload-conflict": [];
  previous: [];
  next: [];
  close: [];
}>();

const translatedText = defineModel<string>("translatedText", { required: true });
const status = defineModel<string>("status", { required: true });
const translatorNotes = defineModel<string>("translatorNotes", { required: true });
const voStatus = defineModel<string>("voStatus", { required: true });

const sourceIcon = computed(() => (text.sourceType === "flow_node" ? Workflow : FileText));
const saving = computed(() => editorState.saveState === "saving");
const saveBlocked = computed(() => saving.value || editorState.placeholderIssue !== null);
const history = computed(() => ({
  translatedBy: text.translatedBy,
  lastTranslatedAt: text.lastTranslatedAt,
  machineTranslated: text.machineTranslated,
}));
</script>

<template>
  <section
    class="flex min-h-0 flex-col overflow-hidden rounded-lg border border-border bg-card"
    :aria-label="$t('localization.workbench.editor_label')"
    data-testid="localization-editor"
  >
    <header class="flex items-center gap-3 border-b border-border py-3 pr-3 pl-3 lg:pl-5">
      <Button
        variant="ghost"
        size="icon-sm"
        class="lg:hidden"
        :aria-label="$t('localization.editor.close')"
        @click="emit('close')"
      >
        <ChevronLeft class="size-4" />
      </Button>

      <div class="flex min-w-0 flex-1 flex-col gap-1.5">
        <component
          :is="text.sourceRef.url ? LiveLink : 'span'"
          :to="text.sourceRef.url ?? undefined"
          class="inline-flex min-w-0 items-center gap-1.5 self-start text-[13px] text-muted-foreground"
          :class="text.sourceRef.url && 'hover:text-foreground'"
          :title="text.sourceRef.url ? $t('localization.editor.open_source') : undefined"
        >
          <component :is="sourceIcon" class="size-[13px] shrink-0" aria-hidden="true" />
          <span class="truncate">
            <template v-if="text.sourceRef.parent">{{ text.sourceRef.parent }} › </template
            >{{ text.sourceRef.label }}
          </span>
          <ExternalLink v-if="text.sourceRef.url" class="size-3 shrink-0" aria-hidden="true" />
        </component>
        <div class="flex flex-wrap items-center gap-2">
          <StatusBadge :status="status" variant="pill" />
          <TextFlag v-if="text.stale" kind="outdated" variant="pill" />
          <TextFlag v-if="text.machineTranslated" kind="machine" variant="pill" />
          <span
            v-if="!canEdit"
            class="inline-flex items-center gap-1 rounded-full bg-muted py-0.5 pr-2.5 pl-2 text-xs font-medium text-muted-foreground"
          >
            <Lock class="size-3" />
            {{ $t("localization.editor.read_only") }}
          </span>
          <span
            v-if="text.speakerName"
            class="inline-flex items-center gap-1.5 text-xs text-muted-foreground"
          >
            <UserAvatar :display-name="text.speakerName" size="xs" />
            {{ text.speakerName }}
          </span>
          <span class="text-xs text-muted-foreground">
            {{ text.contentRoleLabel
            }}<template v-if="text.voEligible">
              · {{ $t("localization.editor.vo_eligible") }}</template
            >
          </span>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-0.5">
        <span
          v-if="navigation.positionLabel"
          class="mr-1.5 hidden text-xs tabular-nums text-muted-foreground sm:inline"
        >
          {{ navigation.positionLabel }}
        </span>
        <Button
          variant="ghost"
          size="icon-sm"
          :disabled="!navigation.hasPrevious"
          :aria-label="$t('localization.editor.previous')"
          @click="emit('previous')"
        >
          <ChevronLeft class="size-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon-sm"
          :disabled="!navigation.hasNext"
          :aria-label="$t('localization.editor.next')"
          @click="emit('next')"
        >
          <ChevronRight class="size-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon-sm"
          class="hidden lg:inline-flex"
          :aria-label="$t('localization.editor.close')"
          @click="emit('close')"
        >
          <X class="size-4" />
        </Button>
      </div>
    </header>

    <div class="flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto px-4 pt-4 pb-3 lg:px-5 lg:pt-5">
      <p v-if="!canEdit" class="text-xs text-muted-foreground">
        {{ $t("localization.editor.read_only_hint") }}
      </p>

      <OutdatedBanner
        v-if="text.stale"
        :can-edit="canEdit"
        :busy="saving"
        :placeholders-blocked="editorState.placeholderIssue !== null"
        @confirm="emit('confirm-current')"
      />

      <ConflictBanner
        v-if="editorState.saveState === 'conflict'"
        @overwrite="emit('retry-conflict')"
        @reload="emit('reload-conflict')"
      />

      <SourcePane
        :text="text"
        :source-name="sourceName"
        :placeholder-issue="editorState.placeholderIssue"
        :has-translation="translatedText.trim() !== ''"
      />

      <TranslationPane
        v-model="translatedText"
        :target-name="text.localeName"
        :can-edit="canEdit"
        :has-provider="hasProvider"
        :save-state="editorState.saveState"
        :placeholder-issue="editorState.placeholderIssue"
        :placeholder-count="text.placeholders.length"
        :translating="editorState.translating"
        @save="emit('save')"
        @save-next="emit('save-next')"
        @translate="emit('translate')"
      />

      <p
        v-if="editorState.saveState === 'error' && editorState.saveError"
        class="text-xs text-destructive"
        role="alert"
      >
        {{ editorState.saveError }}
      </p>

      <EditorMeta
        v-model:status="status"
        v-model:vo-status="voStatus"
        v-model:translator-notes="translatorNotes"
        :can-edit="canEdit"
        :vo-eligible="text.voEligible"
        :final-unavailable="editorState.finalUnavailable"
        :history="history"
      />
    </div>

    <footer
      v-if="canEdit"
      class="flex items-center gap-2 border-t border-border bg-card px-4 py-3 lg:px-5"
    >
      <Button :disabled="saveBlocked" data-testid="localization-save" @click="emit('save')">
        {{ $t("localization.editor.save") }}
      </Button>
      <Button
        variant="outline"
        :disabled="saveBlocked || !navigation.hasNext"
        data-testid="localization-save-next"
        @click="emit('save-next')"
      >
        {{ $t("localization.editor.save_next") }}
        <ArrowRight class="size-3.5" />
      </Button>
      <span class="ml-auto hidden text-xs whitespace-nowrap text-muted-foreground sm:inline">
        {{ $t("localization.editor.shortcuts") }}
      </span>
    </footer>
  </section>
</template>
