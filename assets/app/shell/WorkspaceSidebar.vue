<script setup lang="ts">
import { LayoutDashboard, User, Briefcase, LogOut } from "lucide-vue-next";
import { computed } from "vue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import UserAvatar from "@components/UserAvatar.vue";
import { useI18n } from "vue-i18n";
import type { WorkspaceItem, WorkspaceUser } from "./workspaceLayoutTypes";

const { t } = useI18n();

const {
  currentUser,
  workspaces = [],
  currentWorkspaceSlug = null,
} = defineProps<{
  currentUser: WorkspaceUser;
  workspaces?: WorkspaceItem[];
  currentWorkspaceSlug?: string | null;
}>();

const displayName = computed(
  () => currentUser.displayName || currentUser.email?.split("@")[0] || "",
);

const handleLogout = () => {
  const token = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
  const form = document.createElement("form");
  form.method = "POST";
  form.action = "/users/log-out";

  const methodInput = document.createElement("input");
  methodInput.type = "hidden";
  methodInput.name = "_method";
  methodInput.value = "delete";
  form.appendChild(methodInput);

  if (token) {
    const csrfInput = document.createElement("input");
    csrfInput.type = "hidden";
    csrfInput.name = "_csrf_token";
    csrfInput.value = token;
    form.appendChild(csrfInput);
  }

  document.body.appendChild(form);
  form.submit();
};
</script>

<template>
  <div class="flex flex-col h-full">
    <!-- Header -->
    <div class="px-4 py-4 border-b border-border/10">
      <img
        :src="'/images/logos/logo-name-black.png'"
        alt="Storyarn"
        class="h-7 w-auto dark:hidden"
      />
      <img
        :src="'/images/logos/logo-name-white.png'"
        alt="Storyarn"
        class="hidden h-7 w-auto dark:block"
      />
    </div>

    <!-- Workspaces List -->
    <div class="flex-1 overflow-y-auto px-2 py-4 space-y-1">
      <div class="px-2 pb-2 text-xs font-medium text-muted-foreground">
        {{ t("workspace.sidebar.my_workspaces") }}
      </div>

      <a
        v-for="ws in workspaces"
        :key="ws.id"
        :href="`/workspaces/${ws.slug}`"
        data-phx-link="redirect"
        data-phx-link-state="push"
        :class="[
          'flex items-center gap-2 px-2 py-2 rounded-md text-sm transition-colors',
          ws.slug === currentWorkspaceSlug
            ? 'bg-accent text-accent-foreground font-medium'
            : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
        ]"
      >
        <Briefcase class="size-4 shrink-0" />
        <span class="truncate">{{ ws.name }}</span>
      </a>
    </div>

    <!-- User Profile Dropdown at bottom -->
    <div class="pt-2 pb-2 px-2 border-t border-border/10 mt-auto">
      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <button
            class="flex items-center gap-2 w-full p-2 rounded-md hover:bg-accent transition-colors text-left group"
          >
            <UserAvatar
              :email="currentUser.email"
              :display-name="currentUser.displayName"
              size="sm"
            />
            <div class="flex flex-col overflow-hidden">
              <span
                class="text-sm font-medium truncate text-foreground group-hover:text-foreground/90 transition-colors"
                >{{ displayName }}</span
              >
              <span class="text-xs text-muted-foreground truncate">{{ currentUser.email }}</span>
            </div>
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" :side-offset="4" class="w-full min-w-56">
          <DropdownMenuItem as-child>
            <a
              href="/users/settings"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="flex items-center gap-2"
            >
              <User class="size-4" />
              {{ t("workspace.sidebar.account_settings") }}
            </a>
          </DropdownMenuItem>
          <DropdownMenuItem as-child>
            <a
              href="/workspaces"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="flex items-center gap-2"
            >
              <LayoutDashboard class="size-4" />
              {{ t("workspace.sidebar.all_workspaces") }}
            </a>
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            @select.prevent="handleLogout"
            class="flex items-center gap-2 text-destructive cursor-pointer"
          >
            <LogOut class="size-4" />
            {{ t("workspace.sidebar.log_out") }}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  </div>
</template>
