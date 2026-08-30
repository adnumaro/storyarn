<script setup lang="ts">
import { Clock3, Crown, Loader2, Trash2, X } from "@lucide/vue";
import { ref, watch } from "vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
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
import { useMemberInvitations } from "@shared/composables/useMemberInvitations";

interface ProjectMember {
  id: number;
  user_id: string;
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
  canTransferOwnership = false,
} = defineProps<{
  members?: ProjectMember[];
  pendingInvitations?: PendingInvitation[];
  currentUserId?: string | null;
  canTransferOwnership?: boolean;
}>();

const transferTarget = ref<ProjectMember | null>(null);
const transferDialogOpen = ref(false);
const transferPending = ref(false);
const transferTransportFailed = ref(false);
let transferAttempt = 0;

const {
  live,
  inviteEmail,
  inviteRole,
  invitationPending,
  revokingInvitationId,
  sendInvitation,
  revokeInvitation,
  formatExpiry,
} = useMemberInvitations("editor");

function removeMember(id: number) {
  live.pushEvent("remove_member", { id: String(id) });
}

function requestOwnershipTransfer(member: ProjectMember) {
  if (!canTransferOwnership) return;

  transferTarget.value = member;
  transferTransportFailed.value = false;
  transferDialogOpen.value = true;
}

function transferOwnership() {
  if (!canTransferOwnership || !transferTarget.value || transferPending.value) return;

  const targetUserId = transferTarget.value.user_id;
  const attempt = ++transferAttempt;
  transferPending.value = true;
  transferTransportFailed.value = false;

  live.pushEvent(
    "transfer_owner",
    { "user-id": String(targetUserId) },
    () => {
      if (attempt === transferAttempt) resetOwnershipTransfer();
    },
    () => {
      if (attempt !== transferAttempt) return;

      transferPending.value = false;
      transferTransportFailed.value = true;
    },
  );
}

function cancelOwnershipTransfer() {
  resetOwnershipTransfer();
}

function resetOwnershipTransfer() {
  transferAttempt += 1;
  transferTarget.value = null;
  transferDialogOpen.value = false;
  transferPending.value = false;
  transferTransportFailed.value = false;
}

watch(
  () => canTransferOwnership,
  (canTransfer) => {
    if (!canTransfer) resetOwnershipTransfer();
  },
);

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
        class="flex flex-col gap-3 rounded-lg border border-border p-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex min-w-0 items-center gap-3">
          <div
            class="flex size-9 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-medium"
          >
            {{ memberInitials(member) }}
          </div>
          <div class="min-w-0">
            <p class="truncate font-medium">{{ memberDisplayName(member) }}</p>
            <p v-if="member.display_name" class="truncate text-sm text-muted-foreground">
              {{ member.email }}
            </p>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2 sm:justify-end">
          <Badge :variant="roleBadgeVariant[member.role] || 'outline'">
            {{ member.role }}
          </Badge>
          <Button
            v-if="
              canTransferOwnership && member.role !== 'owner' && member.user_id !== currentUserId
            "
            :id="`transfer-project-ownership-${member.user_id}`"
            variant="outline"
            size="sm"
            class="gap-1.5"
            @click="requestOwnershipTransfer(member)"
          >
            <Crown class="size-3.5" aria-hidden="true" />
            {{ $t("project_settings.members.transfer.action") }}
          </Button>
          <Button
            v-if="member.role !== 'owner' && member.user_id !== currentUserId"
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
        :id="`project-pending-invitation-${invitation.id}`"
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

    <ConfirmDialog
      v-model:open="transferDialogOpen"
      :title="$t('project_settings.members.transfer.title')"
      :description="
        $t('project_settings.members.transfer.description', {
          name: transferTarget ? memberDisplayName(transferTarget) : '',
        })
      "
      :confirm-text="$t('project_settings.members.transfer.confirm')"
      :cancel-text="$t('project_settings.members.transfer.cancel')"
      :pending="transferPending"
      :pending-text="$t('project_settings.members.transfer.pending')"
      :close-on-confirm="false"
      :error="
        transferTransportFailed
          ? $t('project_settings.members.transfer.connection_unconfirmed')
          : undefined
      "
      variant="warning"
      :icon="Crown"
      @confirm="transferOwnership"
      @cancel="cancelOwnershipTransfer"
    />
  </div>
</template>
