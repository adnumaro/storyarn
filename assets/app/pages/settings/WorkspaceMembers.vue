<script setup>
import { Trash2 } from "lucide-vue-next";
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
  canManage: { type: Boolean, default: false }
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
    <section>
      <h3 class="text-lg font-semibold mb-4">Team Members</h3>
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
            
            <template v-if="canManage && member.role !== 'owner' && member.id !== currentUserId">
              <Select :model-value="member.role" @update:model-value="(val) => changeRole(member.id, val)">
                <SelectTrigger class="w-[110px] h-8 text-xs">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="admin">Admin</SelectItem>
                  <SelectItem value="member">Member</SelectItem>
                  <SelectItem value="viewer">Viewer</SelectItem>
                </SelectContent>
              </Select>
            </template>
            <template v-else>
              <Badge :variant="roleBadgeVariant[member.role] || 'outline'">
                {{ member.role }}
              </Badge>
            </template>
            
            <Button
              v-if="canManage && member.role !== 'owner' && member.id !== currentUserId"
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
    </section>

    <Separator />

    <section>
      <h3 class="text-lg font-semibold mb-4">Request member invitation</h3>
      <p class="text-sm text-muted-foreground mb-3">
        Invitation requests are reviewed by an admin before being sent.
      </p>
      <form @submit.prevent="sendInvitation" class="border border-border/40 bg-muted/20 p-4 rounded-lg">
        <div class="flex gap-3 items-start">
          <div class="flex-1 space-y-1.5">
            <Label for="invite-email">Email address</Label>
            <Input
              id="invite-email"
              type="email"
              v-model="inviteEmail"
              placeholder="colleague@example.com"
              required
            />
          </div>
          <div class="w-32 space-y-1.5">
            <Label for="invite-role">Role</Label>
            <Select v-model="inviteRole">
              <SelectTrigger class="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="admin">Admin</SelectItem>
                <SelectItem value="member">Member</SelectItem>
                <SelectItem value="viewer">Viewer</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-4">
          <Button type="submit">Request Invitation</Button>
        </div>
      </form>
    </section>
  </div>
</template>
