<script setup>
import { computed, ref } from "vue";
import { FolderOpen, Plus, Search, Settings } from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import { Separator } from "@/vue/components/ui/separator/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import { formatRelativeTime } from "@/vue/lib/date-utils.js";

const props = defineProps({
	workspace: { type: Object, required: true },
	membership: { type: Object, required: true },
	projects: { type: Array, default: () => [] },
	searchQuery: { type: String, default: "" },
	canCreateProject: { type: Boolean, default: false },
	newProjectUrl: { type: String, default: null },
	settingsUrl: { type: String, default: null },
});

const live = useLive();

const localSearch = ref(props.searchQuery);

function onSearch(e) {
	localSearch.value = e.target.value;
	live.pushEvent("search", { search: e.target.value });
}

const canManage = computed(() =>
	["owner", "admin"].includes(props.membership.role),
);

const canCreate = computed(() =>
	["owner", "admin", "member"].includes(props.membership.role),
);
</script>

<template>
  <!-- Workspace Banner -->
  <header class="relative">
    <div
      :class="[
        'h-48 overflow-hidden rounded-xl',
        !workspace.banner_url && 'bg-gradient-to-r from-primary/20 to-secondary/20',
      ]"
    >
      <img
        v-if="workspace.banner_url"
        :src="workspace.banner_url"
        alt=""
        class="w-full h-full object-cover"
      />
    </div>

    <div class="absolute bottom-0 left-0 right-0 p-6 bg-gradient-to-t from-background/90 to-transparent">
      <div class="flex items-end justify-between">
        <div>
          <h1 class="text-3xl font-bold">{{ workspace.name }}</h1>
          <p v-if="workspace.description" class="text-muted-foreground mt-1 max-w-2xl">
            {{ workspace.description }}
          </p>
        </div>
        <a
          v-if="canManage && settingsUrl"
          :href="settingsUrl"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="inline-flex items-center justify-center size-9 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
        >
          <Settings class="size-4" />
        </a>
      </div>
    </div>
  </header>

  <!-- Toolbar -->
  <div class="pt-4 pb-2 flex items-center justify-between">
    <div class="flex items-center gap-2">
      <div class="relative">
        <Search class="absolute left-2.5 top-1/2 -translate-y-1/2 size-4 text-muted-foreground" />
        <Input
          type="text"
          placeholder="Search projects..."
          class="pl-9 h-8 w-64"
          :value="localSearch"
          @input="onSearch"
        />
      </div>
    </div>

    <a
      v-if="canCreate && canCreateProject && newProjectUrl"
      :href="newProjectUrl"
      data-phx-link="patch"
      data-phx-link-state="push"
    >
      <Button size="sm">
        <Plus class="size-4 mr-1" />
        New Project
      </Button>
    </a>
    <div
      v-else-if="canCreate && !canCreateProject"
      class="relative group"
    >
      <Button size="sm" disabled>
        <Plus class="size-4 mr-1" />
        New Project
      </Button>
      <div class="absolute right-0 top-full mt-1 px-2 py-1 text-xs rounded bg-popover border border-border shadow-md opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none z-10">
        Project limit reached for your plan
      </div>
    </div>
  </div>

  <!-- Projects Grid -->
  <div class="pt-2">
    <div
      v-if="projects.length > 0"
      class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
    >
      <a
        v-for="projectData in projects"
        :key="projectData.project.id"
        :href="projectData.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="rounded-lg border border-border bg-surface p-4 space-y-2 hover:bg-muted/30 transition-colors cursor-pointer"
      >
        <div class="text-xs text-muted-foreground">
          {{ projectData.project.inserted_at_formatted }}
        </div>
        <h3 class="text-base font-semibold">{{ projectData.project.name }}</h3>
        <p v-if="projectData.project.description" class="text-sm text-muted-foreground line-clamp-2">
          {{ projectData.project.description }}
        </p>
        <div class="flex items-center justify-end mt-2">
          <span class="text-xs text-muted-foreground">
            {{ formatRelativeTime(projectData.project.updated_at) }}
          </span>
        </div>
      </a>
    </div>

    <!-- Empty states -->
    <div v-if="projects.length === 0 && !localSearch" class="flex flex-col items-center justify-center py-12 text-center">
      <FolderOpen class="size-12 text-muted-foreground/40 mb-4" />
      <h3 class="text-lg font-medium mb-1">No projects yet</h3>
      <p class="text-sm text-muted-foreground">Create your first project to get started</p>
    </div>

    <div v-if="projects.length === 0 && localSearch" class="flex flex-col items-center justify-center py-12 text-center">
      <Search class="size-12 text-muted-foreground/40 mb-4" />
      <h3 class="text-lg font-medium mb-1">No projects found</h3>
      <p class="text-sm text-muted-foreground">Try a different search term</p>
    </div>
  </div>
</template>
