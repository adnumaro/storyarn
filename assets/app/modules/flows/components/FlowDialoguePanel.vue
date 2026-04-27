<script setup lang="ts">
/**
 * Side panel for editing a dialogue flow_node.
 *
 * Vue port of V1's `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`
 * LiveComponent (V1 also misnamed it — this panel has nothing to do with the
 * Storyarn.Screenplays domain; it edits a `type="dialogue"` flow_node).
 *
 * Three tabs: Text, Responses, Settings.
 */

import Placeholder from "@tiptap/extension-placeholder";
import StarterKit from "@tiptap/starter-kit";
import { EditorContent, useEditor } from "@tiptap/vue-3";
import { BookOpen, MessageSquare, Settings, X } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import EntityCombobox from "@components/form-fields/EntityCombobox.vue";
import ExpressionEditor from "@components/ExpressionEditor.vue";
import type { Assignment, ConditionData } from "@components/builders/types";
import Sidebar from "@components/layout/Sidebar.vue";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs/index.ts";
import type { Variable } from "@modules/shared/variables";
import { useI18n } from "vue-i18n";
import { useLive } from "@composables/useLive";

interface NodeResponse {
  id: string | number;
  text: string;
  // The backend persists condition as a string (V1 contract: handler stores
  // `value` verbatim, evaluator does `is_binary` guard). The ConditionBuilder
  // takes a ConditionData object — we parse on read, stringify on push.
  condition?: string | ConditionData | null;
  instruction_assignments?: Assignment[];
}

interface DialogueNodeData {
  text?: string;
  speaker_sheet_id?: number | string | null;
  stage_directions?: string;
  menu_text?: string;
  technical_id?: string;
  responses?: NodeResponse[];
}

interface DialogueNodeShape {
  id: number | string;
  data: DialogueNodeData;
}

interface SheetOption {
  id: number | string;
  name: string;
}

const {
  open = false,
  node = null,
  canEdit = false,
  allSheets = [],
  projectVariables = [],
} = defineProps<{
  open?: boolean;
  node?: DialogueNodeShape | null;
  canEdit?: boolean;
  allSheets?: SheetOption[];
  projectVariables?: Variable[] | string;
}>();

const { t } = useI18n();
const live = useLive();
const activeTab = ref("text");

const parsedVariables = computed<Variable[]>(() => {
  if (Array.isArray(projectVariables)) return projectVariables;
  try {
    return JSON.parse(projectVariables);
  } catch {
    return [];
  }
});
const nodeData = computed<DialogueNodeData>(() => node?.data || {});
const speakerId = computed<number | string | null>(() => nodeData.value.speaker_sheet_id || null);
const speakerOptions = computed(() => allSheets.map((s) => ({ id: s.id, name: s.name })));
const responses = computed<NodeResponse[]>(() => nodeData.value.responses || []);

// TipTap editor for dialogue text
let debounceTimer: ReturnType<typeof setTimeout> | undefined;
const editor = useEditor({
  extensions: [
    StarterKit,
    Placeholder.configure({ placeholder: t("flows.dialogue_panel.dialogue_placeholder") }),
  ],
  editable: canEdit,
  content: nodeData.value.text || "",
  onUpdate: ({ editor: ed }) => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      live.pushEvent("update_node_text", {
        id: node?.id,
        content: ed.getHTML(),
      });
    }, 500);
  },
});

// Sync editor content when node changes
watch(
  () => nodeData.value.text,
  (newText) => {
    if (editor.value && newText !== editor.value.getHTML()) {
      editor.value.commands.setContent(newText || "", { emitUpdate: false });
    }
  },
);

function close() {
  live.pushEvent("close_editor", {});
}

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

// Wire keys match the V1 backend handler pattern-match exactly:
// `Dialogue.Node.handle_*_response` expect "response-id" / "node-id" /
// "value" / "assignments". Hyphenated keys are required (LiveView matches
// on string keys with hyphens). Don't switch to underscore.

function addResponse(): void {
  if (!node) return;
  live.pushEvent("add_response", { "node-id": node.id });
}

function removeResponse(responseId: string | number): void {
  if (!node) return;
  live.pushEvent("remove_response", {
    "response-id": responseId,
    "node-id": node.id,
  });
}

function updateResponseText(responseId: string | number, text: string): void {
  if (!node) return;
  live.pushEvent("update_response_text", {
    "response-id": responseId,
    "node-id": node.id,
    value: text,
  });
}

function updateResponseCondition(
  responseId: string | number,
  condition: ConditionData | null | undefined,
): void {
  if (!node) return;
  // Backend stores condition as a string (or "" → nil). Stringify the
  // builder's structured payload before pushing; clear with "".
  const value = condition == null ? "" : JSON.stringify(condition);
  live.pushEvent("update_response_condition", {
    "response-id": responseId,
    "node-id": node.id,
    value,
  });
}

function updateResponseAssignments(
  responseId: string | number,
  updatedAssignments: Assignment[],
): void {
  if (!node) return;
  live.pushEvent("update_response_instruction_builder", {
    "response-id": responseId,
    "node-id": node.id,
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
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <BookOpen class="size-4" />
          {{ $t("flows.dialogue_panel.title") }}
        </div>
        <button
          type="button"
          class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
          @click="close"
        >
          <X class="size-4" />
        </button>
      </div>
    </template>

    <div v-if="node" class="space-y-4">
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
              :model-value="nodeData.stage_directions || ''"
              :placeholder="$t('flows.dialogue_panel.stage_directions_placeholder')"
              class="mt-1 text-sm italic"
              :disabled="!canEdit"
              @blur="updateStageDirections"
            />
          </div>

          <!-- Dialogue text (TipTap) -->
          <div>
            <Label class="text-xs">{{ $t("flows.dialogue_panel.dialogue") }}</Label>
            <div
              class="mt-1 rounded-md border border-input bg-background p-3 min-h-[120px] prose prose-sm dark:prose-invert max-w-none"
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
                  :variables="parsedVariables"
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
                  :assignments="resp.instruction_assignments || []"
                  :variables="parsedVariables"
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
          <div>
            <Label class="text-xs">{{ $t("flows.dialogue_panel.menu_text") }}</Label>
            <Input
              :model-value="nodeData.menu_text || ''"
              :placeholder="$t('flows.dialogue_panel.menu_text_placeholder')"
              class="mt-1"
              :disabled="!canEdit"
              @blur="updateMenuText"
            />
          </div>
          <div>
            <Label class="text-xs">{{ $t("flows.dialogue_panel.technical_id") }}</Label>
            <Input
              :model-value="nodeData.technical_id || ''"
              :placeholder="$t('flows.dialogue_panel.technical_id_placeholder')"
              class="mt-1 font-mono text-xs"
              :disabled="!canEdit"
              @blur="updateTechnicalId"
            />
          </div>
        </TabsContent>
      </Tabs>
    </div>
  </Sidebar>
</template>
