<script setup lang="ts">
import { X } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import Sidebar from "@shell/Sidebar.vue";
import type { Variable } from "@shared/domain/variables.ts";
import { useLive } from "@shared/composables/useLive.ts";
import ConnectionProperties from "./properties/ConnectionProperties.vue";
import PinProperties from "./properties/PinProperties.vue";
import ZoneProperties from "./properties/ZoneProperties.vue";

const { t } = useI18n();

interface ProjectEntity {
  id: number | string;
  name: string;
  shortcut?: string;
}

interface SelectedElementData {
  id: number | string;
  [key: string]: unknown;
}

const TITLES = computed<Record<string, string>>(() => ({
  zone: t("scenes.element_properties.zone"),
  pin: t("scenes.element_properties.pin"),
  connection: t("scenes.element_properties.connection"),
  annotation: t("scenes.element_properties.annotation"),
}));

const {
  selectedType = null,
  selectedElement = null,
  canEdit = false,
  elementPanelOpen = false,
  projectSheets = [],
  projectFlows = [],
  projectScenes = [],
  projectVariables = [],
} = defineProps<{
  selectedType: string | null;
  selectedElement: SelectedElementData | null;
  canEdit: boolean;
  elementPanelOpen: boolean;
  projectSheets: ProjectEntity[];
  projectFlows: ProjectEntity[];
  projectScenes: ProjectEntity[];
  projectVariables: Variable[];
}>();

const live = useLive();

const isOpen = computed(() => elementPanelOpen && selectedElement != null);

function close() {
  live.pushEvent("close_element_panel", {});
}
</script>

<template>
  <Sidebar side="right" :open="isOpen" @close="close">
    <template #header>
      <div class="flex items-center gap-2 py-2.5">
        <span class="font-medium text-sm flex-1">{{
          (selectedType && TITLES[selectedType]) || $t("scenes.element_properties.fallback")
        }}</span>
        <button
          type="button"
          class="inline-flex items-center justify-center size-6 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
          :title="$t('scenes.element_properties.close')"
          :aria-label="$t('scenes.element_properties.close')"
          @click="close"
        >
          <X class="size-3" />
        </button>
      </div>
    </template>

    <div v-if="selectedElement" class="py-2">
      <PinProperties
        v-if="selectedType === 'pin'"
        :element="selectedElement"
        :can-edit="canEdit"
        :project-sheets="projectSheets"
        :project-flows="projectFlows"
        :project-variables="projectVariables"
      />

      <ZoneProperties
        v-else-if="selectedType === 'zone'"
        :element="selectedElement"
        :can-edit="canEdit"
        :project-scenes="projectScenes"
        :project-sheets="projectSheets"
        :project-flows="projectFlows"
        :project-variables="projectVariables"
      />

      <ConnectionProperties
        v-else-if="selectedType === 'connection'"
        :element="selectedElement"
        :can-edit="canEdit"
      />
    </div>
  </Sidebar>
</template>
