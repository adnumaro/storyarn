<script setup lang="ts">
/**
 * Body of the dialogue node editor — tabs (Text / Responses / Settings) +
 * TipTap body editor + all save handlers. Wrapper-agnostic: consumed by
 * `FlowDialoguePanel.vue` (Sidebar) and `FlowDialogueFullscreenEditor.vue`
 * (Dialog modal). Owns no shell chrome (no header / footer) — the wrapper
 * component renders those.
 *
 * Exports the typed `DialoguePanelData` and friends so test fixtures and
 * sibling consumers share a single nominal type.
 */

import { EditorContent } from "@tiptap/vue-3";
import { Check, Copy, MessageSquare, RefreshCw, Settings, Volume2 } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import AudioAsset from "@components/assets/AudioAsset.vue";
import EntityCombobox from "@components/form-fields/EntityCombobox.vue";
import ExpressionEditor from "@components/ExpressionEditor.vue";
import type { Assignment, ConditionData } from "@components/builders/types";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs/index.ts";
import { useScreenplayEditor } from "@modules/flows/composables/useScreenplayEditor";
import type { Variable } from "@modules/shared/variables";
import { useI18n } from "vue-i18n";
import { useLive } from "@composables/useLive";

export interface AudioAssetItem {
  id: number | string;
  filename: string;
  url?: string | null;
}

export interface SheetOption {
  id: number | string;
  name: string;
}

export interface DialogueResponseShape {
  id: string | number;
  text: string;
  // Backend persists `condition` as a string (V1 contract: handler stores
  // `value` verbatim, evaluator does is_binary). ConditionBuilder takes a
  // ConditionData object — we parse on read, stringify on push.
  condition?: string | ConditionData | null;
  instructionAssignments?: Assignment[];
  hasTypeWarnings?: boolean;
}

/** Camel-cased payload built by `build_dialogue_panel_data/2` server-side
 * (D5 in REFACTOR.md §10). Single typed prop instead of N loose ones —
 * mirrors FlowSequenceConfigPanel. Exported so test fixtures + sibling
 * consumers (FlowDialoguePanel, FlowDialogueFullscreenEditor) share the
 * exact same nominal type. */
export interface DialoguePanelData {
  nodeId: number | string;
  speakerSheetId: number | string | null;
  text: string;
  stageDirections: string;
  menuText: string;
  technicalId: string;
  localizationId: string;
  audioAssetId: number | string | null;
  avatarId: number | string | null;
  responses: DialogueResponseShape[];
  allSheets: SheetOption[];
  audioAssets: AudioAssetItem[];
  projectVariables: Variable[];
}

const {
  data = null,
  canEdit = false,
} = defineProps<{
  data?: DialoguePanelData | null;
  canEdit?: boolean;
}>();

const { t } = useI18n();
const live = useLive();
const activeTab = ref("text");

const nodeId = computed<number | string | null>(() => data?.nodeId ?? null);
const speakerId = computed<number | string | null>(() => data?.speakerSheetId ?? null);
const speakerOptions = computed(() =>
  (data?.allSheets ?? []).map((s) => ({ id: s.id, name: s.name })),
);
const responses = computed<DialogueResponseShape[]>(() => data?.responses ?? []);
const audioAssetId = computed<number | string | null>(() => data?.audioAssetId ?? null);
const projectVariables = computed<Variable[]>(() => data?.projectVariables ?? []);

// Screenplay-format editor (no marks / no block extensions). Single source
// of truth shared with the canvas inline editor in DialogueNode.vue.
let debounceTimer: ReturnType<typeof setTimeout> | undefined;
const editor = useScreenplayEditor({
  placeholder: t("flows.dialogue_panel.dialogue_placeholder"),
  editable: canEdit,
  content: data?.text || "",
  onUpdate: (ed) => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      const id = nodeId.value;
      if (id == null) return;
      live.pushEvent("update_node_text", {
        id,
        content: ed.getHTML(),
      });
    }, 500);
  },
});

// Sync editor content when the panel data changes (server-pushed refresh).
watch(
  () => data?.text,
  (newText) => {
    if (editor.value && newText !== editor.value.getHTML()) {
      editor.value.commands.setContent(newText || "", { emitUpdate: false });
    }
  },
);

function updateSpeaker(sheetId: number | string | null): void {
  live.pushEvent("update_node_field", {
    field: "speaker_sheet_id",
    value: sheetId,
  });
}

function updateStageDirections(e: Event): void {
  live.pushEvent("update_node_field", {
    field: "stage_directions",
    value: (e.target as HTMLInputElement).value,
  });
}

function updateMenuText(e: Event): void {
  live.pushEvent("update_node_field", {
    field: "menu_text",
    value: (e.target as HTMLInputElement).value,
  });
}

function updateTechnicalId(e: Event): void {
  live.pushEvent("update_node_field", {
    field: "technical_id",
    value: (e.target as HTMLInputElement).value,
  });
}

function updateLocalizationId(e: Event): void {
  live.pushEvent("update_node_field", {
    field: "localization_id",
    value: (e.target as HTMLInputElement).value,
  });
}

function generateTechnicalId(): void {
  // V1 wire: empty params, server resolves from selected_node.
  live.pushEvent("generate_technical_id", {});
}

// "Copied" feedback timer — resets to false 1.5s after copy.
const localizationJustCopied = ref(false);
let copiedResetTimer: ReturnType<typeof setTimeout> | undefined;
async function copyLocalizationId(): Promise<void> {
  const value = data?.localizationId;
  if (!value) return;
  try {
    await navigator.clipboard.writeText(value);
    localizationJustCopied.value = true;
    if (copiedResetTimer) clearTimeout(copiedResetTimer);
    copiedResetTimer = setTimeout(() => {
      localizationJustCopied.value = false;
    }, 1500);
  } catch {
    // Clipboard API unavailable (insecure origin / older browser); silent.
  }
}

// D2 from REFACTOR.md §10: drop the V1 :audio_picker PubSub, route through
// update_node_field. Mirrors how FlowSequenceConfigPanel writes background_asset_id.
function selectAudio(asset: AudioAssetItem): void {
  live.pushEvent("update_node_field", {
    field: "audio_asset_id",
    value: asset.id,
  });
}

function clearAudio(): void {
  live.pushEvent("update_node_field", {
    field: "audio_asset_id",
    value: null,
  });
}

// Wire keys match the V1 backend handler pattern-match exactly:
// `Dialogue.Node.handle_*_response` expect "response-id" / "node-id" /
// "value" / "assignments". Hyphenated keys are required (LiveView matches
// on string keys with hyphens). Don't switch to underscore.

function addResponse(): void {
  if (nodeId.value == null) return;
  live.pushEvent("add_response", { "node-id": nodeId.value });
}

function removeResponse(responseId: string | number): void {
  if (nodeId.value == null) return;
  live.pushEvent("remove_response", {
    "response-id": responseId,
    "node-id": nodeId.value,
  });
}

function updateResponseText(responseId: string | number, text: string): void {
  if (nodeId.value == null) return;
  live.pushEvent("update_response_text", {
    "response-id": responseId,
    "node-id": nodeId.value,
    value: text,
  });
}

function updateResponseCondition(
  responseId: string | number,
  condition: ConditionData | null | undefined,
): void {
  if (nodeId.value == null) return;
  // Backend stores condition as a string (or "" → nil). Stringify the
  // builder's structured payload before pushing; clear with "".
  const value = condition == null ? "" : JSON.stringify(condition);
  live.pushEvent("update_response_condition", {
    "response-id": responseId,
    "node-id": nodeId.value,
    value,
  });
}

function updateResponseAssignments(
  responseId: string | number,
  updatedAssignments: Assignment[],
): void {
  if (nodeId.value == null) return;
  live.pushEvent("update_response_instruction_builder", {
    "response-id": responseId,
    "node-id": nodeId.value,
    assignments: updatedAssignments,
  });
}

// Parse a condition string back into the object the builder consumes.
// Tolerates: undefined, null, "", a stringified object, or an already-parsed
// object (defensive — old data may still be in object form).
function parseConditionForBuilder(
  raw: string | ConditionData | null | undefined,
): ConditionData | undefined {
  if (raw == null || raw === "") return undefined;
  if (typeof raw === "string") {
    try {
      return JSON.parse(raw) as ConditionData;
    } catch {
      return undefined;
    }
  }
  return raw as ConditionData;
}
</script>

<template>
  <div v-if="data" class="space-y-4">
    <Tabs v-model="activeTab">
      <TabsList class="w-full">
        <TabsTrigger value="text" class="flex-1 gap-1 text-xs">
          <MessageSquare class="size-3.5" />
          {{ $t("flows.dialogue_panel.tab_text") }}
        </TabsTrigger>
        <TabsTrigger value="responses" class="flex-1 gap-1 text-xs">
          {{ $t("flows.dialogue_panel.tab_responses") }}
        </TabsTrigger>
        <TabsTrigger value="settings" class="flex-1 gap-1 text-xs">
          <Settings class="size-3.5" />
          {{ $t("flows.dialogue_panel.tab_settings") }}
        </TabsTrigger>
      </TabsList>

      <!-- Text Tab -->
      <TabsContent value="text" class="space-y-3 mt-3">
        <!-- Speaker -->
        <EntityCombobox
          :label="$t('flows.dialogue_panel.speaker')"
          :options="speakerOptions"
          :selected-id="speakerId"
          :placeholder="$t('flows.dialogue_panel.no_speaker')"
          :disabled="!canEdit"
          @update:selected-id="updateSpeaker"
        />

        <!-- Stage directions -->
        <div>
          <Label class="text-xs">{{ $t("flows.dialogue_panel.stage_directions") }}</Label>
          <Input
            :model-value="data?.stageDirections || ''"
            :placeholder="$t('flows.dialogue_panel.stage_directions_placeholder')"
            class="mt-1 text-sm italic"
            :disabled="!canEdit"
            @blur="updateStageDirections"
          />
        </div>

        <!-- Menu text (relocated from Settings — mirrors inline-edit field
             order: stage_directions → menu_text → dialogue body). -->
        <div>
          <Label class="text-xs">{{ $t("flows.dialogue_panel.menu_text") }}</Label>
          <Input
            :model-value="data?.menuText || ''"
            :placeholder="$t('flows.dialogue_panel.menu_text_placeholder')"
            class="mt-1"
            :disabled="!canEdit"
            @blur="updateMenuText"
          />
        </div>

        <!-- Dialogue text (TipTap) — screenplay-format body. Wrapper click
             focuses the editor so the entire textarea-look surface is a
             focus target (M2.1). Screenplay typography (Courier Prime)
             applied via scoped :deep(.tiptap). -->
        <div>
          <Label class="text-xs">{{ $t("flows.dialogue_panel.dialogue") }}</Label>
          <div
            class="dialogue-body mt-1 rounded-md border border-input bg-background dark:bg-card p-3 transition-[color,box-shadow] focus-within:border-ring focus-within:ring-ring/50 focus-within:ring-[3px]"
            @click="editor?.commands.focus()"
          >
            <EditorContent :editor="editor" />
          </div>
        </div>
      </TabsContent>

      <!-- Responses Tab -->
      <TabsContent value="responses" class="space-y-3 mt-3">
        <div
          v-for="resp in responses"
          :key="resp.id"
          class="border border-border rounded-lg p-3 space-y-2"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-muted-foreground">{{
              $t("flows.dialogue_panel.response")
            }}</span>
            <button
              v-if="canEdit"
              type="button"
              class="text-xs text-destructive hover:text-destructive/80"
              @click="removeResponse(resp.id)"
            >
              {{ $t("flows.dialogue_panel.remove") }}
            </button>
          </div>
          <Input
            :model-value="resp.text || ''"
            :placeholder="$t('flows.dialogue_panel.response_placeholder')"
            :disabled="!canEdit"
            @blur="
              (e: FocusEvent) => updateResponseText(resp.id, (e.target as HTMLInputElement).value)
            "
          />

          <!-- Condition (collapsible) — Builder | Code tabs -->
          <details v-if="canEdit" class="text-xs">
            <summary class="cursor-pointer text-muted-foreground hover:text-foreground">
              {{ $t("flows.dialogue_panel.condition") }}
            </summary>
            <div class="mt-2">
              <ExpressionEditor
                mode="condition"
                :condition="parseConditionForBuilder(resp.condition)"
                :variables="projectVariables"
                :disabled="!canEdit"
                @update:condition="(c) => updateResponseCondition(resp.id, c)"
              />
            </div>
          </details>

          <!-- Instructions (collapsible) — Builder | Code tabs -->
          <details v-if="canEdit" class="text-xs">
            <summary class="cursor-pointer text-muted-foreground hover:text-foreground">
              {{ $t("flows.dialogue_panel.instructions") }}
            </summary>
            <div class="mt-2">
              <ExpressionEditor
                mode="instruction"
                :assignments="resp.instructionAssignments || []"
                :variables="projectVariables"
                :disabled="!canEdit"
                @update:assignments="(a) => updateResponseAssignments(resp.id, a)"
              />
            </div>
          </details>
        </div>

        <Button v-if="canEdit" variant="outline" size="sm" class="w-full" @click="addResponse">
          {{ $t("flows.dialogue_panel.add_response") }}
        </Button>
      </TabsContent>

      <!-- Settings Tab -->
      <TabsContent value="settings" class="space-y-3 mt-3">
        <!-- Audio asset (V1 had AudioPicker LiveComponent here; D2 routes
             via update_node_field, mirroring sequence config). Reuses the
             shared AudioAsset component. -->
        <div>
          <Label class="text-xs">{{ $t("flows.dialogue_panel.audio") }}</Label>
          <AudioAsset
            class="mt-1"
            :label="$t('flows.dialogue_panel.audio')"
            :icon="Volume2"
            :asset-id="audioAssetId"
            :audio-assets="data?.audioAssets ?? []"
            :can-edit="canEdit"
            :pick-placeholder="$t('flows.dialogue_panel.pick_audio')"
            :search-placeholder="$t('flows.dialogue_panel.search_audio')"
            :clear-title="$t('flows.dialogue_panel.clear_audio')"
            @select="selectAudio"
            @clear="clearAudio"
          />
        </div>

        <div>
          <Label class="text-xs">{{ $t("flows.dialogue_panel.technical_id") }}</Label>
          <div class="flex items-center gap-1 mt-1">
            <Input
              :model-value="data?.technicalId || ''"
              :placeholder="$t('flows.dialogue_panel.technical_id_placeholder')"
              class="font-mono text-xs flex-1"
              :disabled="!canEdit"
              @blur="updateTechnicalId"
            />
            <Button
              v-if="canEdit"
              variant="ghost"
              size="icon"
              class="size-8 shrink-0"
              :title="$t('flows.dialogue_panel.generate_technical_id')"
              @click="generateTechnicalId"
            >
              <RefreshCw class="size-3.5" />
            </Button>
          </div>
        </div>

        <div>
          <Label class="text-xs">{{ $t("flows.dialogue_panel.localization_id") }}</Label>
          <div class="flex items-center gap-1 mt-1">
            <Input
              :model-value="data?.localizationId || ''"
              :placeholder="$t('flows.dialogue_panel.localization_id_placeholder')"
              class="font-mono text-xs flex-1"
              :disabled="!canEdit"
              @blur="updateLocalizationId"
            />
            <Button
              v-if="data?.localizationId"
              variant="ghost"
              size="icon"
              class="size-8 shrink-0"
              :title="
                localizationJustCopied
                  ? $t('flows.dialogue_panel.copied')
                  : $t('flows.dialogue_panel.copy_localization_id')
              "
              @click="copyLocalizationId"
            >
              <Check v-if="localizationJustCopied" class="size-3.5 text-emerald-500" />
              <Copy v-else class="size-3.5" />
            </Button>
          </div>
        </div>
      </TabsContent>
    </Tabs>
  </div>
</template>

<style scoped>
/* Screenplay-format typography for the dialogue body editor. Courier Prime
 * is loaded globally by `assets/css/screenplay.css`. */
.dialogue-body {
  cursor: text;
}

.dialogue-body :deep(.tiptap) {
  font-family: "Courier Prime", "Courier New", Courier, monospace;
  font-size: 14px;
  line-height: 1.4;
  outline: none;
  /* 5-line minimum visible area (5 × 1.4em). */
  min-height: 7em;
  /* TipTap/ProseMirror injects cursor:pointer at runtime (not via stylesheet);
   * !important is the only way to override without forking the editor. */
  cursor: text !important;
}

.dialogue-body :deep(.tiptap p) {
  margin: 0;
}

.dialogue-body :deep(.tiptap p.is-editor-empty:first-child::before) {
  content: attr(data-placeholder);
  float: left;
  color: var(--color-muted-foreground);
  pointer-events: none;
  height: 0;
}
</style>
