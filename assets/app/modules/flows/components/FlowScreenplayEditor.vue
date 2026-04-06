<script setup>
/**
 * Screenplay editor for dialogue nodes.
 * Replaces the V1 LiveComponent with a Vue sidebar.
 *
 * Three tabs: Text, Responses, Settings.
 */

import Placeholder from "@tiptap/extension-placeholder";
import StarterKit from "@tiptap/starter-kit";
import { EditorContent, useEditor } from "@tiptap/vue-3";
import { BookOpen, MessageSquare, Settings, X } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import EntityCombobox from "@components/form-fields/EntityCombobox.vue";
import InstructionBuilder from "@components/builders/InstructionBuilder.vue";
import Sidebar from "@components/layout/Sidebar.vue";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs/index.js";
import { useLive } from "@composables/useLive.js";

const { open, node, canEdit, allSheets, projectVariables } = defineProps({
  open: { type: Boolean, default: false },
  node: { type: Object, default: null },
  canEdit: { type: Boolean, default: false },
  allSheets: { type: Array, default: () => [] },
  projectVariables: { default: () => [] },
});

const live = useLive();
const activeTab = ref("text");

const parsedVariables = computed(() => {
  if (Array.isArray(projectVariables)) return projectVariables;
  try {
    return JSON.parse(projectVariables);
  } catch {
    return [];
  }
});
const nodeData = computed(() => node?.data || {});
const speakerId = computed(() => nodeData.value.speaker_sheet_id || null);
const speakerOptions = computed(() => allSheets.map((s) => ({ id: s.id, name: s.name })));
const responses = computed(() => nodeData.value.responses || []);

// TipTap editor for dialogue text
let debounceTimer = null;
const editor = useEditor({
  extensions: [StarterKit, Placeholder.configure({ placeholder: "Write dialogue..." })],
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
      editor.value.commands.setContent(newText || "", false);
    }
  },
);

function close() {
  live.pushEvent("close_editor", {});
}

function updateSpeaker(sheetId) {
  live.pushEvent("update_node_field", {
    field: "speaker_sheet_id",
    value: sheetId,
  });
}

function updateStageDirections(e) {
  live.pushEvent("update_node_field", {
    field: "stage_directions",
    value: e.target.value,
  });
}

function updateMenuText(e) {
  live.pushEvent("update_node_field", {
    field: "menu_text",
    value: e.target.value,
  });
}

function updateTechnicalId(e) {
  live.pushEvent("update_node_field", {
    field: "technical_id",
    value: e.target.value,
  });
}

function addResponse() {
  live.pushEvent("add_response", {});
}

function removeResponse(responseId) {
  live.pushEvent("remove_response", { response_id: responseId });
}

function updateResponseText(responseId, text) {
  live.pushEvent("update_response_text", { response_id: responseId, text });
}

function updateResponseCondition(responseId, condition) {
  live.pushEvent("update_response_condition", {
    response_id: responseId,
    condition,
  });
}

function updateResponseAssignments(responseId, assignments) {
  live.pushEvent("update_response_assignments", {
    response_id: responseId,
    assignments,
  });
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between px-3 py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <BookOpen class="size-4" />
          Screenplay Editor
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
            Text
          </TabsTrigger>
          <TabsTrigger value="responses" class="flex-1 gap-1 text-xs"> Responses </TabsTrigger>
          <TabsTrigger value="settings" class="flex-1 gap-1 text-xs">
            <Settings class="size-3.5" />
            Settings
          </TabsTrigger>
        </TabsList>

        <!-- Text Tab -->
        <TabsContent value="text" class="space-y-3 mt-3">
          <!-- Speaker -->
          <EntityCombobox
            label="Speaker"
            :options="speakerOptions"
            :selected-id="speakerId"
            placeholder="No speaker"
            :disabled="!canEdit"
            @update:selected-id="updateSpeaker"
          />

          <!-- Stage directions -->
          <div>
            <Label class="text-xs">Stage directions</Label>
            <Input
              :model-value="nodeData.stage_directions || ''"
              placeholder="e.g., looks away nervously"
              class="mt-1 text-sm italic"
              :disabled="!canEdit"
              @blur="updateStageDirections"
            />
          </div>

          <!-- Dialogue text (TipTap) -->
          <div>
            <Label class="text-xs">Dialogue</Label>
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
              <span class="text-xs font-medium text-muted-foreground">Response</span>
              <button
                v-if="canEdit"
                type="button"
                class="text-xs text-destructive hover:text-destructive/80"
                @click="removeResponse(resp.id)"
              >
                Remove
              </button>
            </div>
            <Input
              :model-value="resp.text || ''"
              placeholder="Response text..."
              :disabled="!canEdit"
              @blur="(e) => updateResponseText(resp.id, e.target.value)"
            />

            <!-- Condition (collapsible) -->
            <details v-if="canEdit" class="text-xs">
              <summary class="cursor-pointer text-muted-foreground hover:text-foreground">
                Condition
              </summary>
              <div class="mt-2">
                <ConditionBuilder
                  :condition="resp.condition"
                  :variables="parsedVariables"
                  :disabled="!canEdit"
                  @update:condition="(c) => updateResponseCondition(resp.id, c)"
                />
              </div>
            </details>

            <!-- Instructions (collapsible) -->
            <details v-if="canEdit" class="text-xs">
              <summary class="cursor-pointer text-muted-foreground hover:text-foreground">
                Instructions
              </summary>
              <div class="mt-2">
                <InstructionBuilder
                  :assignments="resp.instruction_assignments || []"
                  :variables="parsedVariables"
                  :disabled="!canEdit"
                  @update:assignments="(a) => updateResponseAssignments(resp.id, a)"
                />
              </div>
            </details>
          </div>

          <Button v-if="canEdit" variant="outline" size="sm" class="w-full" @click="addResponse">
            + Add Response
          </Button>
        </TabsContent>

        <!-- Settings Tab -->
        <TabsContent value="settings" class="space-y-3 mt-3">
          <div>
            <Label class="text-xs">Menu text</Label>
            <Input
              :model-value="nodeData.menu_text || ''"
              placeholder="Short text for menus..."
              class="mt-1"
              :disabled="!canEdit"
              @blur="updateMenuText"
            />
          </div>
          <div>
            <Label class="text-xs">Technical ID</Label>
            <Input
              :model-value="nodeData.technical_id || ''"
              placeholder="auto-generated"
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
