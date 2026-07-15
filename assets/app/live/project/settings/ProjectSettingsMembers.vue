<script setup lang="ts">
import { Clock3, Loader2, Trash2, X } from "lucide-vue-next";
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Label } from "@components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from "@shared/composables/useLive";

interface ProjectMember {
  id: number;
  display_name?: string;
  email: string;
  role: string;
}

interface PendingInvitation {
  id: number;
  email: string;
  role: string;
  expires_at: string;
}

const {
  members = [],
  pendingInvitations = [],
  currentUserId = null,
} = defineProps<{
  members?: ProjectMember[];
  pendingInvitations?: PendingInvitation[];
  currentUserId?: number | null;
}>();

const live = useLive();
const { locale } = useI18n({ useScope: "global" });

const inviteEmail = ref("");
const inviteRole = ref("editor");
const invitationPending = ref(false);
const revokingInvitationId = ref<number | null>(null);

live.handleEvent("invitation_sent", () => {
  inviteEmail.value = "";
  inviteRole.value = "editor";
});

function sendInvitation() {
  if (invitationPending.value) return;

  invitationPending.value = true;
  live.pushEvent(
    "send_invitation",
    {
      invite: {
        email: inviteEmail.value,
        role: inviteRole.value,
      },
    },
    () => (invitationPending.value = false),
    () => (invitationPending.value = false),
  );
}

function revokeInvitation(id: number) {
  if (revokingInvitationId.value !== null) return;

  revokingInvitationId.value = id;
  live.pushEvent(
    "revoke_invitation",
    { id: String(id) },
    () => (revokingInvitationId.value = null),
    () => (revokingInvitationId.value = null),
  );
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

function formatExpiry(expiresAt: string) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: "medium" }).format(new Date(expiresAt));
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
      <h4 class="font-medium mb-3">{{ $t("project_settings.members.invite_title") }}</h4>
      <p class="text-sm text-muted-foreground mb-3">
        {{ $t("project_settings.members.invite_description") }}
      </p>
      <form id="project-invite-form" @submit.prevent="sendInvitation">
        <div class="flex gap-3 items-end">
          <div class="flex-1 space-y-1.5">
            <Label for="invite-email">{{ $t("project_settings.members.email") }}</Label>
            <Input
              id="invite-email"
              type="email"
              v-model="inviteEmail"
              :placeholder="$t('project_settings.members.email_placeholder')"
              maxlength="160"
              required
            />
          </div>
          <div class="w-32 space-y-1.5">
            <Label for="invite-role">{{ $t("project_settings.members.role") }}</Label>
            <Select v-model="inviteRole">
              <SelectTrigger id="invite-role">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="editor">{{
                  $t("project_settings.members.role_editor")
                }}</SelectItem>
                <SelectItem value="viewer">{{
                  $t("project_settings.members.role_viewer")
                }}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-4">
          <Button type="submit" :disabled="invitationPending">
            <Loader2 v-if="invitationPending" class="size-4 animate-spin" aria-hidden="true" />
            {{ $t("project_settings.members.submit") }}
          </Button>
        </div>
      </form>
    </div>

    <section
      v-if="pendingInvitations.length > 0"
      id="project-pending-invitations"
      class="space-y-3"
    >
      <div>
        <h4 class="font-medium">{{ $t("project_settings.members.pending_title") }}</h4>
        <p class="text-sm text-muted-foreground">
          {{ $t("project_settings.members.pending_description") }}
        </p>
      </div>

      <div
        v-for="invitation in pendingInvitations"
        :key="invitation.id"
        class="flex flex-col gap-3 rounded-lg border border-border p-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="min-w-0">
          <p class="truncate font-medium">{{ invitation.email }}</p>
          <div class="mt-1 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <Badge variant="outline">
              {{ $t("project_settings.members.role_" + invitation.role) }}
            </Badge>
            <span class="inline-flex items-center gap-1">
              <Clock3 class="size-3.5" />
              {{
                $t("project_settings.members.expires", {
                  date: formatExpiry(invitation.expires_at),
                })
              }}
            </span>
          </div>
        </div>
        <Button
          :id="`revoke-project-invitation-${invitation.id}`"
          type="button"
          variant="ghost"
          size="sm"
          class="text-destructive hover:text-destructive"
          :disabled="revokingInvitationId !== null"
          @click="revokeInvitation(invitation.id)"
        >
          <Loader2
            v-if="revokingInvitationId === invitation.id"
            class="size-4 animate-spin"
            aria-hidden="true"
          />
          <X v-else class="size-4" aria-hidden="true" />
          {{ $t("project_settings.members.revoke") }}
        </Button>
      </div>
    </section>
  </div>
</template>
