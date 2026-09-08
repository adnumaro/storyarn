<script setup lang="ts">
import { computed } from "vue";
import { Group, Ungroup, ListPlus } from "@lucide/vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useBoardText } from "../composables/useBoardText";
import type { Idea, IdeaGroup } from "../types";
const { notes, groups, privateMode, busy } = defineProps<{
  notes: Idea[];
  groups: IdeaGroup[];
  privateMode: boolean;
  busy: boolean;
}>();
const emit = defineEmits<{
  create: [];
  membership: [groupId: number, ids: number[], add: boolean];
}>();
const { t } = useBoardText();
const shared = computed(
  () => notes.length > 0 && notes.every((note) => note.id > 0 && note.visibility === "shared"),
);
const memberships = computed(() =>
  groups.filter((group) => group.idea_ids.some((id) => notes.some((note) => note.id === id))),
);
const ungrouped = computed(() => shared.value && !memberships.value.length);
const hint = computed(() => {
  if (privateMode) return t("ideation.groups.privateHelp");
  if (!shared.value) return t("ideation.groups.sharedHelp");
  if (memberships.value.length) return t("ideation.groups.alreadyGrouped");
  return t("ideation.groups.createHelp");
});
</script>
<template>
  <div class="flex items-center gap-1">
    <ToolbarTooltip v-if="notes.length >= 2" :label="hint">
      <button
        id="create-idea-group"
        type="button"
        class="toolbar-btn gap-1.5 px-2.5 disabled:opacity-45"
        aria-keyshortcuts="Meta+G Control+G"
        :disabled="privateMode || !ungrouped || busy"
        @click="emit('create')"
      >
        <Group class="size-4" /><span>{{ t("ideation.groups.create") }}</span>
      </button>
    </ToolbarTooltip>
    <Popover v-if="ungrouped && groups.length && !privateMode">
      <PopoverTrigger
        class="toolbar-btn gap-1.5 px-2.5"
        :disabled="busy"
        :aria-label="t('ideation.groups.addTo')"
        ><ListPlus class="size-4" /><span v-if="notes.length < 2">{{
          t("ideation.groups.addTo")
        }}</span></PopoverTrigger
      >
      <PopoverContent class="w-64 p-1.5"
        ><p class="px-2 py-1.5 text-xs text-muted-foreground">{{ t("ideation.groups.addTo") }}</p>
        <button
          v-for="group in groups"
          :id="`add-notes-to-group-${group.id}`"
          :key="group.id"
          type="button"
          class="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-sm hover:bg-accent"
          :disabled="busy"
          @click="
            emit(
              'membership',
              group.id,
              notes.map((note) => note.id),
              true,
            )
          "
        >
          <Group class="size-4 shrink-0 text-muted-foreground" /><span class="truncate">{{
            group.title || t("ideation.groups.untitled")
          }}</span>
        </button></PopoverContent
      >
    </Popover>
    <template v-if="!privateMode">
      <ToolbarTooltip
        v-for="group in memberships"
        :key="group.id"
        :label="
          t('ideation.groups.removeHelp', { title: group.title || t('ideation.groups.untitled') })
        "
      >
        <button
          :id="`remove-notes-from-group-${group.id}`"
          type="button"
          class="toolbar-btn gap-1.5 px-2"
          :disabled="busy"
          :aria-label="t('ideation.groups.remove')"
          @click="
            emit(
              'membership',
              group.id,
              notes.map((note) => note.id).filter((id) => group.idea_ids.includes(id)),
              false,
            )
          "
        >
          <Ungroup class="size-4" /><span>{{ t("ideation.groups.remove") }}</span>
        </button>
      </ToolbarTooltip>
    </template>
  </div>
</template>
