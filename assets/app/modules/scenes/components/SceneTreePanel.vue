<script setup lang="ts">
import { Layers, Map as MapIcon } from "lucide-vue-next";
import { ref } from "vue";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs";
import SceneLayerList from "./SceneLayerList.vue";
import SceneTree from "./SceneTree.vue";

interface SceneTreeNodeData {
  id: number | string;
  name: string;
  children?: SceneTreeNodeData[];
}

interface LayerItem {
  id: number | string;
  name: string;
  visible: boolean;
  fogEnabled: boolean;
}

const {
  scenesTree = [],
  selectedSceneId = null,
  canEdit = false,
  workspaceSlug,
  projectSlug,
  layers = [],
  activeLayerId = null,
  editMode = true,
  hasScene = false,
  hasLayers = true,
} = defineProps<{
  scenesTree: SceneTreeNodeData[];
  selectedSceneId: string | number | null;
  canEdit: boolean;
  workspaceSlug: string;
  projectSlug: string;
  layers: LayerItem[];
  activeLayerId: number | string | null;
  editMode: boolean;
  hasScene: boolean;
  hasLayers: boolean;
}>();

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
