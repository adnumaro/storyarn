<script setup lang="ts">
import { Crown, Loader2, Mail, Trash2 } from "@lucide/vue";
import { ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { SettingsPage, SettingsRow, SettingsSection } from "@components/settings";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import UserAvatar from "@components/UserAvatar.vue";
import { useMemberInvitations } from "@shared/composables/useMemberInvitations";

interface WorkspaceMember {
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
  canInvite = false,
  canManage = false,
  canTransferOwnership = false,
} = defineProps<{
  members?: WorkspaceMember[];
  pendingInvitations?: PendingInvitation[];
  currentUserId?: string | null;
  canInvite?: boolean;
  canManage?: boolean;
  canTransferOwnership?: boolean;
}>();

const { t } = useI18n();
const roles = ["admin", "member", "viewer"] as const;

const {
  live,
  inviteEmail,
  inviteRole,
  invitationPending,
  revokingInvitationId,
  sendInvitation,
  revokeInvitation,
  formatExpiry,
} = useMemberInvitations("member");

function changeRole(id: number, role: string): void {
  live.pushEvent("change_role", { "member-id": String(id), role });
}

// Removal asks for confirmation; ownership transfer keeps its pending-aware dialog.
const removeTarget = ref<WorkspaceMember | null>(null);
const removeDialogOpen = ref(false);

function requestRemoval(member: WorkspaceMember): void {
  if (!canManage) return;
  removeTarget.value = member;
  removeDialogOpen.value = true;
}

function removeMember(): void {
  if (!canManage || !removeTarget.value) return;
  live.pushEvent("remove_member", { id: String(removeTarget.value.id) });
  removeTarget.value = null;
}

const transferTarget = ref<WorkspaceMember | null>(null);
const transferDialogOpen = ref(false);
const transferPending = ref(false);
const transferTransportFailed = ref(false);
let transferAttempt = 0;

function requestOwnershipTransfer(member: WorkspaceMember): void {
  if (!canTransferOwnership) return;

  transferTarget.value = member;
  transferTransportFailed.value = false;
  transferDialogOpen.value = true;
}

function transferOwnership(): void {
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

function resetOwnershipTransfer(): void {
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

watch(
  () => canManage,
  (manage) => {
    if (!manage) {
      removeDialogOpen.value = false;
      removeTarget.value = null;
    }
  },
);

function memberDisplayName(member: WorkspaceMember): string {
  return member.display_name || member.email;
}

function manageable(member: WorkspaceMember): boolean {
  return canManage && member.role !== "owner" && member.user_id !== currentUserId;
}

type BadgeVariant = "default" | "secondary" | "destructive" | "outline";
const roleBadgeVariant: Record<string, BadgeVariant> = {
  owner: "default",
  admin: "secondary",
  member: "outline",
  viewer: "outline",
};
</script>

<template>
  <SettingsPage :title="t('settings.workspace.members.page_title')">
    <SettingsSection v-if="canInvite" :title="t('settings.workspace.members.invitation.title')">
      <form
        id="workspace-invite-form"
        class="flex flex-wrap items-center gap-2 px-4 py-3.5"
        @submit.prevent="sendInvitation"
      >
        <div class="min-w-0 flex-[1_1_220px]">
          <Input
            id="invite-email"
            v-model="inviteEmail"
            type="email"
            :placeholder="t('settings.workspace.members.invitation.email_placeholder')"
            :aria-label="t('settings.workspace.members.invitation.email')"
            maxlength="160"
            required
          />
        </div>
        <div class="ml-auto flex items-center gap-2">
          <Select v-model="inviteRole">
            <SelectTrigger
              id="invite-role"
              class="w-32"
              :aria-label="t('settings.workspace.members.invitation.role')"
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem v-for="role in roles" :key="role" :value="role">
                {{ t(`settings.workspace.members.roles.${role}`) }}
              </SelectItem>
            </SelectContent>
          </Select>
          <Button type="submit" :disabled="invitationPending">
            <Loader2 v-if="invitationPending" class="size-4 animate-spin" aria-hidden="true" />
            {{ t("settings.workspace.members.invitation.submit") }}
          </Button>
        </div>
      </form>
      <div class="px-4 pb-3.5 text-[13px] text-muted-foreground">
        {{ t("settings.workspace.members.invitation.roles_hint") }}
      </div>
    </SettingsSection>

    <SettingsSection
      v-if="canInvite && pendingInvitations.length > 0"
      id="workspace-pending-invitations"
      :title="t('settings.workspace.members.pending_title')"
      :hint="t('settings.workspace.members.pending_hint')"
    >
      <SettingsRow
        v-for="invitation in pendingInvitations"
        :id="`workspace-pending-invitation-${invitation.id}`"
        :key="invitation.id"
        :label="invitation.email"
        :hint="
          t('settings.workspace.members.expires', { date: formatExpiry(invitation.expires_at) })
        "
      >
        <template #leading>
          <span
            class="flex size-8 shrink-0 items-center justify-center rounded-full border border-dashed border-input text-muted-foreground"
          >
            <Mail class="size-3.5" aria-hidden="true" />
          </span>
        </template>
        <Badge variant="secondary">
          {{ t(`settings.workspace.members.roles.${invitation.role}`) }}
        </Badge>
        <Button
          :id="`revoke-workspace-invitation-${invitation.id}`"
          type="button"
          variant="ghost"
          size="sm"
          :disabled="revokingInvitationId !== null"
          @click="revokeInvitation(invitation.id)"
        >
          <Loader2
            v-if="revokingInvitationId === invitation.id"
            class="size-4 animate-spin"
            aria-hidden="true"
          />
          {{ t("settings.workspace.members.revoke") }}
        </Button>
      </SettingsRow>
    </SettingsSection>

    <SettingsSection
      :title="t('settings.workspace.members.active_members')"
      :hint="t('settings.workspace.members.count', { count: members.length })"
    >
      <div v-if="members.length === 0" class="px-4 py-8 text-center text-sm text-muted-foreground">
        {{ t("settings.workspace.members.no_members") }}
      </div>

      <SettingsRow
        v-for="member in members"
        :key="member.id"
        :label="memberDisplayName(member)"
        :hint="member.display_name ? member.email : null"
      >
        <template #leading>
          <UserAvatar :email="member.email" :display-name="member.display_name" size="sm" />
        </template>

        <Select
          v-if="manageable(member)"
          :model-value="member.role"
          @update:model-value="(value) => changeRole(member.id, String(value))"
        >
          <SelectTrigger class="w-32" :aria-label="t('settings.workspace.members.invitation.role')">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem v-for="role in roles" :key="role" :value="role">
              {{ t(`settings.workspace.members.roles.${role}`) }}
            </SelectItem>
          </SelectContent>
        </Select>
        <Badge v-else :variant="roleBadgeVariant[member.role] || 'outline'">
          {{ member.role ? t(`settings.workspace.members.roles.${member.role}`) : "" }}
        </Badge>

        <Button
          v-if="canTransferOwnership && member.role !== 'owner' && member.user_id !== currentUserId"
          :id="`transfer-workspace-ownership-${member.user_id}`"
          type="button"
          variant="outline"
          size="sm"
          @click="requestOwnershipTransfer(member)"
        >
          <Crown class="size-3.5" aria-hidden="true" />
          {{ t("settings.workspace.members.transfer.action") }}
        </Button>

        <Button
          v-if="manageable(member)"
          :id="`remove-workspace-member-${member.id}`"
          type="button"
          variant="ghost"
          size="icon"
          class="size-8 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
          :title="t('settings.workspace.members.remove_member')"
          :aria-label="t('settings.workspace.members.remove_member')"
          @click="requestRemoval(member)"
        >
          <Trash2 class="size-4" aria-hidden="true" />
        </Button>
      </SettingsRow>

      <template #footer>{{ t("settings.workspace.members.owner_note") }}</template>
    </SettingsSection>

    <ConfirmDialog
      v-model:open="transferDialogOpen"
      :title="t('settings.workspace.members.transfer.title')"
      :description="
        t('settings.workspace.members.transfer.description', {
          name: transferTarget ? memberDisplayName(transferTarget) : '',
        })
      "
      :confirm-text="t('settings.workspace.members.transfer.confirm')"
      :cancel-text="t('settings.workspace.members.transfer.cancel')"
      :pending="transferPending"
      :pending-text="t('settings.workspace.members.transfer.pending')"
      :close-on-confirm="false"
      :error="
        transferTransportFailed
          ? t('settings.workspace.members.transfer.connection_unconfirmed')
          : undefined
      "
      variant="warning"
      :icon="Crown"
      @confirm="transferOwnership"
      @cancel="resetOwnershipTransfer"
    />

    <ConfirmDialog
      v-if="canManage"
      v-model:open="removeDialogOpen"
      :title="t('settings.workspace.members.remove_dialog.title')"
      :description="
        t('settings.workspace.members.remove_dialog.description', {
          name: removeTarget ? memberDisplayName(removeTarget) : '',
        })
      "
      :confirm-text="t('settings.workspace.members.remove_dialog.confirm')"
      :cancel-text="t('settings.workspace.members.remove_dialog.cancel')"
      variant="destructive"
      :icon="Trash2"
      @confirm="removeMember"
    />
  </SettingsPage>
</template>
