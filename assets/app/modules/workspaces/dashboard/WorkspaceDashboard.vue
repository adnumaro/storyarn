<script setup lang="ts">
import { FolderOpen, Menu, Plus, Search, Settings } from "lucide-vue-next";
import { computed, ref } from "vue";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@components/ui/dialog/index.ts";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import type { Form } from "live_vue";
import NewProjectForm from "../forms/NewProjectForm.vue";
import { useLive } from "@shared/composables/useLive";
import { formatRelativeTime } from "@shared/utils/date-utils";

interface Workspace {
  name: string;
  description?: string;
  banner_url?: string;
}

interface Membership {
  role: string;
}

interface Project {
  id: number;
  name: string;
  description?: string;
  inserted_at_formatted: string;
  updated_at: string;
}

interface ProjectData {
  project: Project;
  href: string;
}

interface NewProjectFormValues {
  name: string;
  description: string;
}

const {
  workspace,
  membership,
  projects = [],
  searchQuery = "",
  canCreateProject = false,
  newProjectForm = null,
  settingsUrl = null,
} = defineProps<{
  workspace: Workspace;
  membership: Membership;
  projects?: ProjectData[];
  searchQuery?: string;
  canCreateProject?: boolean;
  newProjectForm?: Form<NewProjectFormValues> | null;
  settingsUrl?: string | null;
}>();

const live = useLive();

const localSearch = ref(searchQuery);

function onSearch(e: Event) {
  const value = (e.target as HTMLInputElement).value;
  localSearch.value = value;
  live.pushEvent("search", { search: value });
}

const canManage = computed(() => ["owner", "admin"].includes(membership.role));

const canCreate = computed(() => ["owner", "admin", "member"].includes(membership.role));

const isNewProjectModalOpen = ref(false);
</script>

<template>
  <div class="surface-panel h-full p-4 w-full flex flex-col">
    <!-- Workspace Banner -->
    <header class="relative">
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
          <Button
            v-if="canManage && settingsUrl"
            as="a"
            variant="ghost"
            size="icon"
            :href="settingsUrl"
            data-phx-link="redirect"
            data-phx-link-state="push"
          >
            <Settings class="size-4" />
          </Button>
        </div>
      </div>

      <div class="absolute bottom-0 left-0 right-0 px-4 py-2">
        <!-- Toolbar -->
        <div class="pt-4 pb-2 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <div class="relative">
              <Search
                class="absolute left-2.5 top-1/2 -translate-y-1/2 size-4 text-muted-foreground"
              />
              <Input
                type="text"
                :placeholder="$t('workspace.dashboard.search_placeholder')"
                class="pl-9 w-64"
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
            {{ $t("workspace.dashboard.new_project") }}
          </Button>
          <div v-else-if="canCreate && !canCreateProject" class="relative group">
            <Button size="sm" disabled>
              <Plus class="size-4 mr-1" />
              {{ $t("workspace.dashboard.new_project") }}
            </Button>
            <div
              class="absolute right-0 top-full mt-1 px-2 py-1 text-xs rounded bg-popover border border-border shadow-md opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none z-10"
            >
              {{ $t("workspace.dashboard.limit_reached") }}
            </div>
          </div>
        </div>
      </div>
    </header>

    <div class="flex-1">
      <!-- Empty states -->
      <div
        v-if="projects.length === 0 && !localSearch"
        class="flex flex-col items-center justify-center py-12 text-center h-full"
      >
        <FolderOpen class="size-12 text-muted-foreground/40 mb-4" />
        <h3 class="text-lg font-medium mb-1">
          {{ $t("workspace.dashboard.empty_projects.title") }}
        </h3>
        <p class="text-sm text-muted-foreground">
          {{ $t("workspace.dashboard.empty_projects.description") }}
        </p>
      </div>

      <div
        v-if="projects.length === 0 && localSearch"
        class="flex flex-col items-center justify-center py-12 text-center h-full"
      >
        <Search class="size-12 text-muted-foreground/40 mb-4" />
        <h3 class="text-lg font-medium mb-1">{{ $t("workspace.dashboard.empty_search.title") }}</h3>
        <p class="text-sm text-muted-foreground">
          {{ $t("workspace.dashboard.empty_search.description") }}
        </p>
      </div>

      <!-- Projects Grid -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 mt-4">
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
              <div class="mt-2 text-sm text-muted-foreground line-clamp-2 min-h-10">
                <template v-if="projectData.project.description">
                  {{ projectData.project.description }}
                </template>
                <template v-else>
                  <span class="italic opacity-50">{{
                    $t("workspace.dashboard.no_description")
                  }}</span>
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
                  {{
                    $t("workspace.dashboard.updated_at", {
                      time: formatRelativeTime(projectData.project.updated_at).toLowerCase(),
                    })
                  }}
                </div>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
  </div>

  <!-- New Project Modal -->
  <Dialog :open="isNewProjectModalOpen" @update:open="(val) => (isNewProjectModalOpen = val)">
    <DialogContent class="sm:max-w-106.25">
      <DialogHeader>
        <DialogTitle class="hidden">{{ $t("workspace.dashboard.new_project") }}</DialogTitle>
      </DialogHeader>
      <NewProjectForm
        v-if="newProjectForm"
        :form="newProjectForm"
        @cancel="isNewProjectModalOpen = false"
      />
    </DialogContent>
  </Dialog>
</template>
