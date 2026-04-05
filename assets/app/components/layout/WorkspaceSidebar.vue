<script setup>
import { LayoutDashboard, User, Briefcase } from "lucide-vue-next";
import { computed } from "vue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import UserAvatar from "./UserAvatar.vue";

const { currentUser, urls, workspaces, currentWorkspaceSlug } = defineProps({
  currentUser: { type: Object, required: true },
  urls: { type: Object, required: true },
  workspaces: { type: Array, default: () => [] },
  currentWorkspaceSlug: { type: String, required: true },
});

const displayName = computed(
  () => currentUser.displayName || currentUser.email?.split("@")[0] || "",
);
</script>

<template>
  <div class="flex flex-col h-full">
    <!-- Header -->
    <div class="px-4 py-4 border-b border-border/10">
      <h2 class="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
        Storyarn
      </h2>
    </div>

    <!-- Workspaces List -->
    <div class="flex-1 overflow-y-auto px-2 py-4 space-y-1">
      <div class="px-2 pb-2 text-xs font-medium text-muted-foreground">My Workspaces</div>
      
      <a
        v-for="ws in workspaces"
        :key="ws.id"
        :href="ws.href"
        :class="[
          'flex items-center gap-2 px-2 py-2 rounded-md text-sm transition-colors',
          ws.slug === currentWorkspaceSlug
            ? 'bg-accent text-accent-foreground font-medium'
            : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground'
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
          <button class="flex items-center gap-2 w-full p-2 rounded-md hover:bg-accent transition-colors text-left group">
            <UserAvatar
              :email="currentUser.email"
              :display-name="currentUser.displayName"
              size="sm"
            />
            <div class="flex flex-col overflow-hidden">
              <span class="text-sm font-medium truncate text-foreground group-hover:text-foreground/90 transition-colors">{{ displayName }}</span>
              <span class="text-xs text-muted-foreground truncate">{{ currentUser.email }}</span>
            </div>
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" :side-offset="4" class="w-full min-w-56">
          <DropdownMenuItem as-child>
            <a :href="urls.accountSettings" class="flex items-center gap-2">
              <User class="size-4" />
              Account settings
            </a>
          </DropdownMenuItem>
          <DropdownMenuItem as-child>
            <a :href="urls.workspaces" class="flex items-center gap-2">
              <LayoutDashboard class="size-4" />
              All workspaces
            </a>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  </div>
</template>
