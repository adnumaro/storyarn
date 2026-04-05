<script setup>
import { FolderOpen, Plus, Search, Settings, Menu } from "lucide-vue-next";
import { computed, ref } from "vue";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@components/ui/dialog/index.js";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import NewProjectForm from "./projects/new.vue";
import { useLive } from "@composables/useLive.js";
import { formatRelativeTime } from "@lib/date-utils.js";

const {
  workspace,
  membership,
  projects,
  searchQuery,
  canCreateProject,
  newProjectForm,
  settingsUrl,
} = defineProps({
  workspace: { type: Object, required: true },
  membership: { type: Object, required: true },
  projects: { type: Array, default: () => [] },
  searchQuery: { type: String, default: "" },
  canCreateProject: { type: Boolean, default: false },
  newProjectForm: { type: Object, default: null },
  settingsUrl: { type: String, default: null },
});

const live = useLive();

const localSearch = ref(searchQuery);

function onSearch(e) {
  localSearch.value = e.target.value;
  live.pushEvent("search", { search: e.target.value });
}

const canManage = computed(() => ["owner", "admin"].includes(membership.role));

const canCreate = computed(() => ["owner", "admin", "member"].includes(membership.role));

const isNewProjectModalOpen = ref(false);
</script>

<template>
  <!-- Workspace Banner -->
  <header class="relative z-10">
    <div
      :class="[
        'h-86 overflow-hidden rounded-xl',
        !workspace.banner_url && 'bg-linear-to-r from-primary to-secondary',
      ]"
    >
      <img
        v-if="workspace.banner_url"
        :src="workspace.banner_url"
        alt=""
        class="w-full h-full object-cover"
      />
    </div>

    <div class="absolute top-0 left-0 right-0 p-6">
      <div class="flex items-end justify-between">
        <div>
          <div class="flex items-center gap-3">
            <label
              for="workspace-sidebar-check"
              class="inline-flex lg:hidden items-center justify-center size-9 rounded-md bg-background/50 backdrop-blur border border-border/50 text-foreground shadow-sm hover:bg-accent hover:text-accent-foreground transition-colors cursor-pointer"
            >
              <Menu class="size-5" />
            </label>
            <h1 class="text-3xl font-bold">{{ workspace.name }}</h1>
          </div>
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

    <div class="absolute bottom-0 left-0 right-0 p-6">
      <!-- Toolbar -->
      <div class="pt-4 pb-2 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <div class="relative">
            <Search
              class="absolute left-2.5 top-1/2 -translate-y-1/2 size-4 text-muted-foreground"
            />
            <Input
              type="text"
              placeholder="Search projects..."
              class="pl-9 h-8 w-64"
              :value="localSearch"
              @input="onSearch"
            />
          </div>
        </div>

        <Button
          v-if="canCreate && canCreateProject && newProjectForm"
          size="sm"
          @click="isNewProjectModalOpen = true"
        >
          <Plus class="size-4 mr-1" />
          New Project
        </Button>
        <div v-else-if="canCreate && !canCreateProject" class="relative group">
          <Button size="sm" disabled>
            <Plus class="size-4 mr-1" />
            New Project
          </Button>
          <div
            class="absolute right-0 top-full mt-1 px-2 py-1 text-xs rounded bg-popover border border-border shadow-md opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none z-10"
          >
            Project limit reached for your plan
          </div>
        </div>
      </div>
    </div>
  </header>

  <!-- Projects Grid -->
  <div class="v2-surface-panel h-full p-4 pt-8">
    <div v-if="projects.length > 0" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
      <a
        v-for="projectData in projects"
        :key="projectData.project.id"
        :href="projectData.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="group flex flex-col rounded-xl border bg-card text-card-foreground shadow-sm hover:border-primary/40 hover:shadow-md hover:-translate-y-0.5 transition-all cursor-pointer overflow-hidden relative"
      >
        <div class="p-5 flex flex-col flex-1">
          <div>
            <h3 class="text-lg font-semibold truncate group-hover:text-primary transition-colors">
              {{ projectData.project.name }}
            </h3>
            <div class="mt-2 text-sm text-muted-foreground line-clamp-2 min-h-[2.5rem]">
              <template v-if="projectData.project.description">
                {{ projectData.project.description }}
              </template>
              <template v-else>
                <span class="italic opacity-50">No description provided</span>
              </template>
            </div>
          </div>

          <div class="mt-auto pt-5">
            <div class="flex items-center justify-between border-t border-border/50 pt-4">
              <div
                class="text-xs text-muted-foreground bg-secondary/50 px-2 py-1 rounded-md font-medium"
              >
                {{ projectData.project.inserted_at_formatted }}
              </div>
              <div class="text-xs font-medium text-muted-foreground/70">
                Updated {{ formatRelativeTime(projectData.project.updated_at).toLowerCase() }}
              </div>
            </div>
          </div>
        </div>
      </a>
    </div>

    <!-- Empty states -->
    <div
      v-if="projects.length === 0 && !localSearch"
      class="flex flex-col items-center justify-center py-12 text-center h-full"
    >
      <FolderOpen class="size-12 text-muted-foreground/40 mb-4" />
      <h3 class="text-lg font-medium mb-1">No projects yet</h3>
      <p class="text-sm text-muted-foreground">Create your first project to get started</p>
    </div>

    <div
      v-if="projects.length === 0 && localSearch"
      class="flex flex-col items-center justify-center py-12 text-center h-full"
    >
      <Search class="size-12 text-muted-foreground/40 mb-4" />
      <h3 class="text-lg font-medium mb-1">No projects found</h3>
      <p class="text-sm text-muted-foreground">Try a different search term</p>
    </div>
  </div>

  <!-- New Project Modal -->
  <Dialog :open="isNewProjectModalOpen" @update:open="(val) => (isNewProjectModalOpen = val)">
    <DialogContent class="sm:max-w-106.25">
      <DialogHeader>
        <DialogTitle class="hidden">New Project</DialogTitle>
      </DialogHeader>
      <NewProjectForm
        v-if="newProjectForm"
        :form="newProjectForm"
        @cancel="isNewProjectModalOpen = false"
      />
    </DialogContent>
  </Dialog>
</template>
