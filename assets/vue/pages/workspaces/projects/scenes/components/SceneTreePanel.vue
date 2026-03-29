<script setup>
import { Layers, Map as MapIcon } from "lucide-vue-next";
import { ref } from "vue";
import {
	Tabs,
	TabsContent,
	TabsList,
	TabsTrigger,
} from "@/vue/components/ui/tabs";
import SceneLayerList from "./SceneLayerList.vue";
import SceneTree from "./SceneTree.vue";

const props = defineProps({
	// SceneTree props
	scenesTree: { type: Array, default: () => [] },
	selectedSceneId: { type: [String, Number], default: null },
	canEdit: { type: Boolean, default: false },
	workspaceSlug: { type: String, required: true },
	projectSlug: { type: String, required: true },
	// Layer props
	layers: { type: Array, default: () => [] },
	activeLayerId: { type: [Number, String], default: null },
	editMode: { type: Boolean, default: true },
	hasScene: { type: Boolean, default: false },
	// When false, only show SceneTree without tabs (used by index)
	hasLayers: { type: Boolean, default: true },
});

const activeTab = ref("layers");
</script>

<template>
  <div class="flex flex-col h-full">
    <!-- With layers: tabs Layers/Scenes (show.ex) -->
    <Tabs v-if="hasLayers" v-model="activeTab" class="flex flex-col h-full">
      <div class="px-2 pt-1 pb-2">
        <TabsList class="w-full">
          <TabsTrigger value="layers" class="flex-1 gap-1 text-xs">
            <Layers class="size-3.5" />
            Layers
          </TabsTrigger>
          <TabsTrigger value="scenes" class="flex-1 gap-1 text-xs">
            <MapIcon class="size-3.5" />
            Scenes
          </TabsTrigger>
        </TabsList>
      </div>

      <TabsContent value="layers" class="flex-1 overflow-y-auto mt-0 px-1">
        <SceneLayerList
          v-if="hasScene"
          :layers="layers"
          :active-layer-id="activeLayerId"
          :can-edit="canEdit"
          :edit-mode="editMode"
        />
        <div v-else class="px-2 py-4 text-xs text-muted-foreground text-center">
          Select a scene to manage layers.
        </div>
      </TabsContent>

      <TabsContent value="scenes" class="flex-1 overflow-y-auto mt-0">
        <SceneTree
          :scenes-tree="scenesTree"
          :selected-scene-id="selectedSceneId"
          :can-edit="canEdit"
          :workspace-slug="workspaceSlug"
          :project-slug="projectSlug"
        />
      </TabsContent>
    </Tabs>

    <!-- Without layers: SceneTree only (index.ex) -->
    <div v-else class="flex-1 overflow-y-auto">
      <SceneTree
        :scenes-tree="scenesTree"
        :selected-scene-id="selectedSceneId"
        :can-edit="canEdit"
        :workspace-slug="workspaceSlug"
        :project-slug="projectSlug"
      />
    </div>
  </div>
</template>
