<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useResizeObserver } from "@vueuse/core";
import {
  Check,
  GripVertical,
  Layers,
  Pencil,
  TextQuote,
  Ungroup,
  X,
  LoaderCircle,
  Trash2,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useBoardText } from "../composables/useBoardText";
import type { GroupBounds } from "../lib/groups";
import type { GroupText, IdeaGroup } from "../types";
const { group, bounds, selected, canEdit, busy, visibleCount, zoom, save } = defineProps<{
  group: IdeaGroup;
  bounds: GroupBounds;
  selected: boolean;
  canEdit: boolean;
  busy: boolean;
  visibleCount: number;
  zoom: number;
  save: (id: number, text: GroupText, version: number) => Promise<boolean>;
}>();
const emit = defineEmits<{
  pointer: [event: PointerEvent, group: IdeaGroup, move: boolean];
  select: [id: number];
  separate: [id: number];
  remove: [id: number];
  reveal: [id: number];
  edit: [id: number, field: "title" | "synthesis"];
  resize: [id: number, height: number];
  synthesisVisibility: [id: number, visible: boolean];
  finish: [];
}>();
const { t } = useBoardText();
const title = ref(group.title ?? "");
const synthesis = ref(group.synthesis ?? "");
const editing = ref<"title" | "synthesis" | null>(null);
const groupFrame = ref<HTMLElement | null>(null);
const titleInput = ref<HTMLInputElement | null>(null);
const synthesisInput = ref<HTMLTextAreaElement | null>(null);
const saving = ref(false);
const failed = ref(false);
let baseVersion = group.version;
const baseline = ref({ title: title.value, synthesis: synthesis.value });
const dirty = computed(
  () => title.value !== baseline.value.title || synthesis.value !== baseline.value.synthesis,
);
const synthesisCard = ref<HTMLElement | null>(null);
const synthesisHeight = ref(180);
useResizeObserver(synthesisCard, (entries) => {
  const height = (entries[0]?.target as HTMLElement | undefined)?.offsetHeight;
  if (height) {
    synthesisHeight.value = height;
    emit("resize", group.id, height);
  }
});
const partial = computed(() => visibleCount < group.idea_ids.length);
const synthesisOpen = computed(
  () =>
    Boolean(group.synthesis) ||
    editing.value === "synthesis" ||
    Boolean(synthesis.value) ||
    !group.idea_ids.length,
);
const displayBounds = computed(() => ({
  ...bounds,
  width: synthesisOpen.value ? Math.max(bounds.width, bounds.synthesisX + 332) : bounds.width,
  height: synthesisOpen.value
    ? Math.max(bounds.height, bounds.synthesisY + synthesisHeight.value + 28)
    : bounds.height,
}));
watch(synthesisOpen, (visible) => emit("synthesisVisibility", group.id, visible), {
  immediate: true,
});
const readableZoom = computed(() => Math.min(1.65, Math.max(1, 0.8 / zoom)));
watch(
  () => [group.title, group.synthesis, group.version] as const,
  ([nextTitle, nextSynthesis]) => {
    if (editing.value || failed.value || saving.value) return;
    title.value = nextTitle ?? "";
    synthesis.value = nextSynthesis ?? "";
    baseVersion = group.version;
    baseline.value = { title: title.value, synthesis: synthesis.value };
  },
);
async function edit(field: "title" | "synthesis") {
  if (!canEdit || busy || saving.value) return;
  emit("select", group.id);
  emit("edit", group.id, field);
  if (!editing.value && !failed.value) baseVersion = group.version;
  editing.value = field;
  await nextTick();
  if (field === "title") {
    titleInput.value?.focus();
    titleInput.value?.select();
  } else synthesisInput.value?.focus();
}
async function commit() {
  if (saving.value || busy || !canEdit) return;
  if (!dirty.value) {
    await cancel();
    return;
  }
  saving.value = true;
  const text = changedFields();
  // A second explicit save after a conflict is the user's reviewed retry.
  const ok = await save(group.id, text, failed.value ? group.version : baseVersion);
  saving.value = false;
  if (ok) await cancel();
  else {
    failed.value = true;
    await focusEditor();
  }
}
function changedFields(): GroupText {
  return {
    ...(title.value !== baseline.value.title ? { title: title.value } : {}),
    ...(synthesis.value !== baseline.value.synthesis ? { synthesis: synthesis.value } : {}),
  };
}
async function cancel() {
  if (saving.value) return;
  title.value = group.title ?? "";
  synthesis.value = group.synthesis ?? "";
  baseVersion = group.version;
  baseline.value = { title: title.value, synthesis: synthesis.value };
  editing.value = null;
  failed.value = false;
  await nextTick();
  emit("finish");
  groupFrame.value?.focus({ preventScroll: true });
}
async function focusEditor() {
  await nextTick();
  const field = editing.value === "title" ? titleInput.value : synthesisInput.value;
  field?.focus({ preventScroll: true });
}
function editorKey(event: KeyboardEvent) {
  event.stopPropagation();
  if (event.isComposing) return;
  if (event.key === "Escape") {
    event.preventDefault();
    cancel();
  }
  if (event.key === "Enter" && (editing.value === "title" || event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    void commit();
  }
}
function pointer(event: PointerEvent) {
  const target = event.target as HTMLElement;
  if (target.closest("input,textarea,button,[data-canvas-chrome]")) return;
  emit("pointer", event, group, Boolean(target.closest("[data-group-drag]")));
}
function keydown(event: KeyboardEvent) {
  if (event.target !== event.currentTarget || event.key !== "Enter") return;
  event.preventDefault();
  event.stopPropagation();
  void edit("title");
}
</script>
<template>
  <article
    ref="groupFrame"
    :id="`canvas-group-${group.id}`"
    :data-group-id="group.id"
    :data-visible-members="visibleCount"
    :data-total-members="group.idea_ids.length"
    tabindex="0"
    :aria-label="group.title || t('ideation.groups.untitled')"
    :aria-selected="selected"
    :aria-busy="saving || busy"
    class="canvas-group absolute left-0 top-0 rounded-xl border outline-none transition-shadow"
    :class="
      selected
        ? 'border-primary/65 ring-2 ring-primary/15'
        : 'border-violet-400/30 dark:border-violet-400/25'
    "
    :style="{
      transform: `translate(${displayBounds.x}px, ${displayBounds.y}px)`,
      width: `${displayBounds.width}px`,
      height: `${displayBounds.height}px`,
      background: 'color-mix(in srgb, var(--primary) 4%, transparent)',
    }"
    @pointerdown.stop="pointer"
    @dblclick.stop
    @keydown="keydown"
    @focus.self="emit('select', group.id)"
  >
    <header
      data-group-drag
      class="absolute inset-x-0 top-0 flex h-16 items-center gap-2 px-5"
      :class="canEdit && !partial && !busy ? 'cursor-grab active:cursor-grabbing' : ''"
    >
      <GripVertical
        aria-hidden="true"
        class="pointer-events-none size-4 shrink-0 text-muted-foreground/60"
      />
      <input
        v-if="editing === 'title'"
        :id="`group-title-${group.id}`"
        ref="titleInput"
        v-model="title"
        :aria-label="t('ideation.groups.title')"
        :placeholder="t('ideation.groups.untitled')"
        :readonly="saving || !canEdit"
        maxlength="160"
        class="min-w-0 flex-1 rounded-md border border-primary/30 bg-background px-2 py-1 text-base font-semibold outline-none focus:ring-2 focus:ring-primary/20"
        @keydown="editorKey"
      />
      <span
        v-else
        data-group-drag
        class="min-w-0 truncate text-[17px] font-semibold tracking-tight"
        @dblclick.stop="edit('title')"
        >{{ group.title || t("ideation.groups.untitled") }}</span
      >
      <span
        v-if="!editing"
        class="pointer-events-none ml-1 shrink-0 text-xs text-muted-foreground"
        >{{ t("ideation.groups.count", { count: group.idea_ids.length }) }}</span
      >
      <div
        v-if="selected && canEdit && !editing"
        data-canvas-chrome
        class="ml-auto flex items-center gap-0.5 rounded-md bg-background/85 p-0.5 shadow-xs"
      >
        <ToolbarTooltip :label="t('ideation.groups.rename')"
          ><button
            :id="`group-title-edit-${group.id}`"
            type="button"
            class="toolbar-btn"
            :aria-label="t('ideation.groups.rename')"
            :disabled="busy"
            @click="edit('title')"
          >
            <Pencil class="size-3.5" /></button
        ></ToolbarTooltip>
        <ToolbarTooltip :label="t('ideation.groups.synthesisHelp')"
          ><button
            :id="`group-synthesis-add-${group.id}`"
            type="button"
            class="toolbar-btn"
            :aria-label="t('ideation.groups.editSynthesis')"
            :disabled="busy"
            @click="edit('synthesis')"
          >
            <TextQuote class="size-4" /></button
        ></ToolbarTooltip>
        <ToolbarTooltip :label="t('ideation.groups.separateHelp')"
          ><button
            :id="`group-separate-${group.id}`"
            type="button"
            class="toolbar-btn"
            :aria-label="t('ideation.groups.separate')"
            :disabled="busy || partial"
            @click="emit('separate', group.id)"
          >
            <Ungroup class="size-4" /></button
        ></ToolbarTooltip>
        <ToolbarTooltip :label="t('ideation.groups.deleteHelp')">
          <button
            :id="`group-delete-${group.id}`"
            type="button"
            class="toolbar-btn hover:text-destructive"
            :aria-label="t('ideation.groups.delete')"
            :disabled="busy"
            @click="emit('remove', group.id)"
          >
            <Trash2 class="size-3.5" />
          </button>
        </ToolbarTooltip>
      </div>
      <div v-if="editing === 'title'" data-canvas-chrome class="flex shrink-0 gap-1">
        <button
          type="button"
          class="toolbar-btn"
          :disabled="saving"
          :aria-label="t('ideation.cancel')"
          @click="cancel"
        >
          <X class="size-4" />
        </button>
        <button
          type="button"
          class="toolbar-btn text-primary"
          :disabled="saving || busy || !canEdit"
          :aria-label="t('ideation.save')"
          @click="commit"
        >
          <LoaderCircle v-if="saving" class="size-4 animate-spin" /><Check v-else class="size-4" />
        </button>
      </div>
    </header>
    <div
      v-if="synthesisOpen"
      ref="synthesisCard"
      data-group-content
      class="group-synthesis absolute rounded-lg border border-violet-300/30 bg-background/95 p-5 shadow-xs"
      :style="{
        left: `${displayBounds.synthesisX}px`,
        top: `${displayBounds.synthesisY}px`,
        width: '304px',
        minHeight: '180px',
        fontSize: `${16 * readableZoom}px`,
      }"
    >
      <div class="mb-3 flex items-center gap-2 text-xs font-medium text-muted-foreground">
        <TextQuote class="size-4" />{{ t("ideation.groups.synthesis")
        }}<button
          v-if="canEdit && !editing"
          type="button"
          class="toolbar-btn ml-auto"
          :aria-label="t('ideation.groups.editSynthesis')"
          :disabled="busy"
          @click="edit('synthesis')"
        >
          <Pencil class="size-3.5" />
        </button>
      </div>
      <textarea
        v-if="editing === 'synthesis'"
        :id="`group-synthesis-${group.id}`"
        ref="synthesisInput"
        v-model="synthesis"
        :aria-label="t('ideation.groups.synthesis')"
        :placeholder="t('ideation.groups.synthesisPlaceholder')"
        :readonly="saving || !canEdit"
        maxlength="10000"
        rows="7"
        class="w-full resize-y select-text rounded-sm bg-transparent leading-relaxed outline-none placeholder:text-muted-foreground/60"
        @keydown="editorKey"
        @pointerdown.stop
        @wheel.stop
      />
      <p
        v-else
        class="whitespace-pre-wrap break-words leading-relaxed"
        :class="!group.synthesis ? 'text-muted-foreground' : ''"
        @dblclick.stop="edit('synthesis')"
      >
        {{ group.synthesis || t("ideation.groups.synthesisPlaceholder") }}
      </p>
      <div
        v-if="editing === 'synthesis'"
        data-canvas-chrome
        class="mt-4 flex justify-end gap-1 border-t pt-3"
      >
        <Button size="sm" variant="ghost" :disabled="saving" @click="cancel">{{
          t("ideation.cancel")
        }}</Button>
        <Button
          :id="`group-synthesis-save-${group.id}`"
          size="sm"
          :disabled="saving || busy || !canEdit"
          @click="commit"
          ><LoaderCircle v-if="saving" class="size-3.5 animate-spin" />{{
            t(failed ? "ideation.groups.saveDraft" : "ideation.save")
          }}</Button
        >
      </div>
    </div>
    <div
      v-if="partial"
      data-canvas-chrome
      class="absolute left-5 top-full mt-2 flex items-center gap-2 rounded-md border bg-background px-3 py-2 text-xs shadow-xs"
    >
      <Layers class="size-3.5 shrink-0 text-muted-foreground" />
      <span>{{
        t("ideation.groups.partial", { visible: visibleCount, total: group.idea_ids.length })
      }}</span>
      <button
        type="button"
        class="font-medium text-primary hover:underline"
        :disabled="busy"
        @click="emit('reveal', group.id)"
      >
        {{ t("ideation.groups.showAll") }}
      </button>
    </div>
    <div
      v-if="failed"
      data-canvas-chrome
      role="alert"
      class="absolute left-5 top-full z-20 mt-2 w-80 rounded-lg border border-amber-300/60 bg-background p-3 text-xs shadow-md"
    >
      <p>{{ t("ideation.groups.draftKept") }}</p>
      <details class="mt-2">
        <summary class="cursor-pointer font-medium">{{ t("ideation.groups.latestText") }}</summary>
        <p class="mt-2 font-medium">{{ group.title || t("ideation.groups.untitled") }}</p>
        <p class="mt-1 whitespace-pre-wrap">{{ group.synthesis }}</p>
      </details>
      <Button class="mt-3" size="sm" :disabled="saving || busy || !canEdit" @click="commit">{{
        t("ideation.groups.saveDraft")
      }}</Button>
    </div>
  </article>
</template>
<style scoped>
.canvas-group {
  min-width: 240px;
}
.group-synthesis {
  overflow-wrap: anywhere;
}
</style>
