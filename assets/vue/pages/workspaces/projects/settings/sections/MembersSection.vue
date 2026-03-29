<script setup>
import { Trash2 } from "lucide-vue-next";
import { ref } from "vue";
import { Badge } from "@/vue/components/ui/badge/index.js";
import { Button } from "@/vue/components/ui/button/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import { Label } from "@/vue/components/ui/label/index.js";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@/vue/components/ui/select/index.js";
import { useLive } from "@/vue/composables/useLive.js";

defineProps({
	members: { type: Array, default: () => [] },
	currentUserId: { type: Number, default: null },
});

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

function removeMember(id) {
	live.pushEvent("remove_member", { id: String(id) });
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
          <div class="size-9 rounded-full bg-muted flex items-center justify-center text-xs font-medium">
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
      <h4 class="font-medium mb-3">Request member invitation</h4>
      <p class="text-sm text-muted-foreground mb-3">
        Invitation requests are reviewed by an admin before being sent.
      </p>
      <form @submit.prevent="sendInvitation">
        <div class="flex gap-3 items-end">
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
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="editor">Editor</SelectItem>
                <SelectItem value="viewer">Viewer</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-4">
          <Button type="submit">Request Invitation</Button>
        </div>
      </form>
    </div>
  </div>
</template>
