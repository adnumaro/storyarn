<script setup lang="ts">
import { LayoutDashboard, User } from "lucide-vue-next";
import { computed } from "vue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@components/ui/tooltip";
import UserAvatar from "./UserAvatar.vue";

interface CurrentUser {
  id: number;
  email: string;
  displayName?: string;
}

interface OnlineUser {
  userId: number;
  email: string;
  displayName?: string;
  color?: string;
}

interface RightToolbarUrls {
  accountSettings: string;
  workspaces: string;
}

const { currentUser, onlineUsers = [], urls } = defineProps<{
  currentUser: CurrentUser;
  onlineUsers?: OnlineUser[];
  urls: RightToolbarUrls;
}>();

const otherUsers = computed(() =>
  onlineUsers.filter((u) => u.userId !== currentUser.id).slice(0, 5),
);

const displayName = computed(
  () => currentUser.displayName || currentUser.email?.split("@")[0] || "",
);
</script>

<template>
  <nav class="flex items-center gap-1 px-1 py-1 v2-surface-panel">
    <!-- Online users -->
    <TooltipProvider v-if="otherUsers.length > 0" :delay-duration="300">
      <div class="flex -space-x-1 mx-1.5">
        <Tooltip v-for="user in otherUsers" :key="user.userId">
          <TooltipTrigger as-child>
            <UserAvatar
              :email="user.email"
              :display-name="user.displayName"
              :color="user.color"
              size="xs"
            />
          </TooltipTrigger>
          <TooltipContent side="bottom">
            {{ user.displayName || user.email }}
          </TooltipContent>
        </Tooltip>
      </div>
    </TooltipProvider>

    <!-- User dropdown -->
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <button class="v2-toolbar-btn rounded-full p-0">
          <UserAvatar
            :email="currentUser.email"
            :display-name="currentUser.displayName"
            size="sm"
          />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" :side-offset="8" class="w-56">
        <div class="px-3 py-2">
          <p class="text-sm font-medium truncate">{{ displayName }}</p>
          <p class="text-xs text-muted-foreground truncate">{{ currentUser.email }}</p>
        </div>
        <DropdownMenuSeparator />
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
  </nav>
</template>
