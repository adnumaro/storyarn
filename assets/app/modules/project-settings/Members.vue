<script setup lang="ts">
import { Trash2 } from "lucide-vue-next";
import { ref } from "vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Button } from "@components/ui/button/index.ts";
import { Input } from "@components/ui/input/index.ts";
import { Label } from "@components/ui/label/index.ts";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select/index.ts";
import { useLive } from "@composables/useLive";

interface ProjectMember {
  id: number;
  display_name?: string;
  email: string;
  role: string;
}

const { members = [], currentUserId = null } = defineProps<{
  members?: ProjectMember[];
  currentUserId?: number | null;
}>();

const live = useLive();

const inviteEmail = ref("");
const inviteRole = ref("editor");

function sendInvitation() {
  live.pushEvent("send_invitation", {
    invite: {
      email: inviteEmail.value,
      role: inviteRole.value,
    },
  });
  inviteEmail.value = "";
}

function removeMember(id: number) {
  live.pushEvent("remove_member", { id: String(id) });
}

function memberDisplayName(member: ProjectMember) {
  return member.display_name || member.email;
}

function memberInitials(member: ProjectMember) {
  const name = member.display_name || member.email;
  return name.substring(0, 2).toUpperCase();
}

type BadgeVariant = "default" | "secondary" | "destructive" | "outline";
const roleBadgeVariant: Record<string, BadgeVariant> = {
  owner: "default",
  admin: "secondary",
  editor: "outline",
  viewer: "outline",
};
</script>

<template>
  <div class="space-y-6">
    <div class="space-y-3">
      <div
        v-for="member in members"
        :key="member.id"
        class="flex items-center justify-between p-3 rounded-lg border border-border"
      >
        <div class="flex items-center gap-3">
          <div
            class="size-9 rounded-full bg-muted flex items-center justify-center text-xs font-medium"
          >
            {{ memberInitials(member) }}
          </div>
          <div>
            <p class="font-medium">{{ memberDisplayName(member) }}</p>
            <p v-if="member.display_name" class="text-sm text-muted-foreground">
              {{ member.email }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <Badge :variant="roleBadgeVariant[member.role] || 'outline'">
            {{ member.role }}
          </Badge>
          <Button
            v-if="member.role !== 'owner' && member.id !== currentUserId"
            variant="ghost"
            size="sm"
            class="text-destructive hover:text-destructive"
            @click="removeMember(member.id)"
          >
            <Trash2 class="size-4" />
          </Button>
        </div>
      </div>
    </div>

    <div class="rounded-lg border border-border bg-muted/30 p-4">
      <h4 class="font-medium mb-3">{{ $t("project_settings.members.request_title") }}</h4>
      <p class="text-sm text-muted-foreground mb-3">
        {{ $t("project_settings.members.request_description") }}
      </p>
      <form @submit.prevent="sendInvitation">
        <div class="flex gap-3 items-end">
          <div class="flex-1 space-y-1.5">
            <Label for="invite-email">{{ $t("project_settings.members.email") }}</Label>
            <Input
              id="invite-email"
              type="email"
              v-model="inviteEmail"
              :placeholder="$t('project_settings.members.email_placeholder')"
              required
            />
          </div>
          <div class="w-32 space-y-1.5">
            <Label for="invite-role">{{ $t("project_settings.members.role") }}</Label>
            <Select v-model="inviteRole">
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="editor">{{ $t("project_settings.members.role_editor") }}</SelectItem>
                <SelectItem value="viewer">{{ $t("project_settings.members.role_viewer") }}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-4">
          <Button type="submit">{{ $t("project_settings.members.submit") }}</Button>
        </div>
      </form>
    </div>
  </div>
</template>
