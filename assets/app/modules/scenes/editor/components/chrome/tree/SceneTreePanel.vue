<script setup lang="ts">
import SceneTree from "./SceneTree.vue";

interface SceneTreeNodeData {
  id: number | string;
  name: string;
  children?: SceneTreeNodeData[];
}

const {
  scenesTree = [],
  selectedSceneId = null,
  canEdit = false,
  workspaceSlug,
  projectSlug,
} = defineProps<{
  scenesTree: SceneTreeNodeData[];
  selectedSceneId: string | number | null;
  canEdit: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex-1 overflow-y-auto">
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
