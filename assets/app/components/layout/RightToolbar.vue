<script setup lang="ts">
import { LayoutDashboard, LogOut, User } from "lucide-vue-next";
import { computed } from "vue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
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
  logout: string;
}

const {
  currentUser,
  onlineUsers = [],
  urls,
} = defineProps<{
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

function handleLogout(): void {
  const token = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
  const form = document.createElement("form");
  form.method = "POST";
  form.action = urls.logout;

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
}
</script>

<template>
  <nav class="flex items-center gap-1 px-1 py-1 surface-panel h-8">
    <!-- Online users -->
    <div v-if="otherUsers.length > 0" class="flex -space-x-1 mx-1.5">
      <ToolbarTooltip
        v-for="user in otherUsers"
        :key="user.userId"
        :label="user.displayName || user.email"
        side="bottom"
      >
        <UserAvatar
          :email="user.email"
          :display-name="user.displayName"
          :color="user.color"
          size="xs"
        />
      </ToolbarTooltip>
    </div>

    <!-- User dropdown -->
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <button class="toolbar-btn rounded-full p-0">
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
            {{ $t("layout.right_toolbar.account_settings") }}
          </a>
        </DropdownMenuItem>
        <DropdownMenuItem as-child>
          <a :href="urls.workspaces" class="flex items-center gap-2">
            <LayoutDashboard class="size-4" />
            {{ $t("layout.right_toolbar.all_workspaces") }}
          </a>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem class="flex items-center gap-2" @select="handleLogout">
          <LogOut class="size-4" />
          {{ $t("layout.right_toolbar.log_out") }}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  </nav>
</template>
