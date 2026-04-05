<script setup>
import { Trash2, UserPlus } from "lucide-vue-next";
import { ref } from "vue";
import { Badge } from "@components/ui/badge/index.js";
import { Button } from "@components/ui/button/index.js";
import { Input } from "@components/ui/input/index.js";
import { Label } from "@components/ui/label/index.js";
import { Separator } from "@components/ui/separator/index.js";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select/index.js";
import { useLive } from "@composables/useLive.js";

const { members, currentUserId, canManage } = defineProps({
  members: { type: Array, default: () => [] },
  currentUserId: { type: Number, default: null },
  canManage: { type: Boolean, default: false },
});

const live = useLive();

const inviteEmail = ref("");
const inviteRole = ref("member");

function sendInvitation() {
  live.pushEvent("send_invitation", {
    invite: {
      email: inviteEmail.value,
      role: inviteRole.value,
    },
  });
  inviteEmail.value = "";
  inviteRole.value = "member";
}

function removeMember(id) {
  live.pushEvent("remove_member", { id: String(id) });
}

function changeRole(id, role) {
  live.pushEvent("change_role", { "member-id": String(id), role });
}

function memberDisplayName(member) {
  return member.display_name || member.email;
}

function memberInitials(member) {
  const name = member.display_name || member.email;
  return name.substring(0, 2).toUpperCase();
}

const roleBadgeVariant = {
  owner: "default",
  admin: "secondary",
  member: "outline",
  viewer: "outline",
};
</script>

<template>
  <div class="space-y-8">
    <div class="space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ $t("settings.workspace.members.title") }}
      </h1>
      <p class="text-base text-muted-foreground">
        {{ $t("settings.workspace.members.subtitle") }}
      </p>
    </div>

    <!-- Invite Member Card -->
    <section
      v-if="canManage"
      class="border border-border/80 bg-card shadow-sm rounded-xl overflow-hidden"
    >
      <div class="px-6 py-5 border-b border-border/50 bg-muted/10 flex flex-col gap-1">
        <h3 class="text-lg font-semibold flex items-center gap-2">
          <UserPlus class="size-4 text-primary" />
          {{ $t("settings.workspace.members.invitation.title") }}
        </h3>
        <p class="text-sm text-muted-foreground">
          {{ $t("settings.workspace.members.invitation.description") }}
        </p>
      </div>
      <div class="p-6">
        <form
          @submit.prevent="sendInvitation"
          class="flex flex-col sm:flex-row gap-4 items-start sm:items-end"
        >
          <div class="flex-1 w-full space-y-1.5">
            <Label
              for="invite-email"
              class="text-xs font-semibold uppercase text-muted-foreground tracking-wider"
              >{{ $t("settings.workspace.members.invitation.email") }}</Label
            >
            <Input
              id="invite-email"
              type="email"
              v-model="inviteEmail"
              :placeholder="$t('settings.workspace.members.invitation.email_placeholder')"
              required
              class="h-10 bg-background"
            />
          </div>
          <div class="w-full sm:w-40 space-y-1.5">
            <Label
              for="invite-role"
              class="text-xs font-semibold uppercase text-muted-foreground tracking-wider"
              >{{ $t("settings.workspace.members.invitation.role") }}</Label
            >
            <Select v-model="inviteRole">
              <SelectTrigger class="w-full h-10! bg-background mb-0">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="admin">{{
                  $t("settings.workspace.members.roles.admin")
                }}</SelectItem>
                <SelectItem value="member">{{
                  $t("settings.workspace.members.roles.member")
                }}</SelectItem>
                <SelectItem value="viewer">{{
                  $t("settings.workspace.members.roles.viewer")
                }}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button
            type="submit"
            class="w-full sm:w-auto h-10 px-6 font-medium shadow-sm transition-transform active:scale-[0.98]"
          >
            {{ $t("settings.workspace.members.invitation.submit") }}
          </Button>
        </form>
      </div>
    </section>

    <!-- Active Members -->
    <section>
      <h3 class="text-lg font-semibold mb-4">
        {{ $t("settings.workspace.members.active_members") }}
      </h3>
      <div
        class="border border-border/80 bg-card rounded-xl shadow-sm overflow-hidden divide-y divide-border/60"
      >
        <!-- Empty state fallback although usually there is at least one owner -->
        <div
          v-if="!members || members.length === 0"
          class="p-8 text-center text-muted-foreground text-sm"
        >
          {{ $t("settings.workspace.members.no_members") }}
        </div>

        <div
          v-for="member in members"
          :key="member.id"
          class="flex flex-col sm:flex-row sm:items-center justify-between p-4 bg-card hover:bg-muted/30 transition-colors gap-4"
        >
          <div class="flex items-center gap-4">
            <div
              class="size-10 rounded-full bg-primary/10 text-primary border border-primary/20 flex flex-shrink-0 items-center justify-center text-sm font-semibold tracking-wide shadow-sm"
            >
              {{ memberInitials(member) }}
            </div>
            <div class="flex flex-col min-w-0">
              <span class="font-medium text-sm leading-tight truncate">{{
                memberDisplayName(member)
              }}</span>
              <span
                v-if="member.display_name"
                class="text-xs text-muted-foreground mt-0.5 truncate"
              >
                {{ member.email }}
              </span>
            </div>
          </div>

          <div class="flex items-center gap-3 sm:ml-auto">
            <template v-if="canManage && member.role !== 'owner' && member.id !== currentUserId">
              <Select
                :model-value="member.role"
                @update:model-value="(val) => changeRole(member.id, val)"
              >
                <SelectTrigger class="w-27.5 h-8 text-xs bg-muted/40 border-border/60 focus:ring-0">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="admin">{{
                    $t("settings.workspace.members.roles.admin")
                  }}</SelectItem>
                  <SelectItem value="member">{{
                    $t("settings.workspace.members.roles.member")
                  }}</SelectItem>
                  <SelectItem value="viewer">{{
                    $t("settings.workspace.members.roles.viewer")
                  }}</SelectItem>
                </SelectContent>
              </Select>
            </template>
            <template v-else>
              <Badge
                :variant="roleBadgeVariant[member.role] || 'outline'"
                class="px-2.5 font-medium shadow-sm"
              >
                {{ member.role ? $t("settings.workspace.members.roles." + member.role) : "" }}
              </Badge>
            </template>

            <Button
              v-if="canManage && member.role !== 'owner' && member.id !== currentUserId"
              variant="ghost"
              size="icon"
              class="size-8 text-muted-foreground hover:text-destructive hover:bg-destructive/10 shrink-0 transition-colors"
              @click="removeMember(member.id)"
              :title="$t('settings.workspace.members.remove_member')"
            >
              <Trash2 class="size-4" />
            </Button>
            <!-- visual placeholder for alignment when trash is not present -->
            <div v-else class="w-8 hidden sm:block"></div>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
