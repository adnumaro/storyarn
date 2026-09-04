<script setup lang="ts">
import { Clock3, Crown, Loader2, UserMinus, X } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { SettingsPage, SettingsSection } from "@components/settings";
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
import UserAvatar from "@components/UserAvatar.vue";
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

const { t } = useI18n();

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

// ---------------------------------------------------------------------------
// Ownership transfer
// ---------------------------------------------------------------------------
const transferTarget = ref<ProjectMember | null>(null);
const transferDialogOpen = ref(false);
const transferPending = ref(false);
const transferTransportFailed = ref(false);
let transferAttempt = 0;

function requestOwnershipTransfer(member: ProjectMember): void {
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

// ---------------------------------------------------------------------------
// Removal
// ---------------------------------------------------------------------------
const removeTarget = ref<ProjectMember | null>(null);
const removeDialogOpen = ref(false);

function requestRemoval(member: ProjectMember): void {
  removeTarget.value = member;
  removeDialogOpen.value = true;
}

function confirmRemoval(): void {
  if (!removeTarget.value) return;

  live.pushEvent("remove_member", { id: String(removeTarget.value.id) });
  removeTarget.value = null;
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------
function memberDisplayName(member: ProjectMember): string {
  return member.display_name || member.email;
}

function canActOn(member: ProjectMember): boolean {
  return member.role !== "owner" && member.user_id !== currentUserId;
}

function roleLabel(role: string): string {
  const key = `project_settings.members.roles.${role}`;
  return t(key);
}

const memberCount = computed(() => t("project_settings.members.count", members.length));
</script>

<template>
  <SettingsPage :title="t('project_settings.members.page_title')">
    <SettingsSection
      :title="t('project_settings.members.invite_section')"
      :hint="t('project_settings.members.roles_hint')"
    >
      <form id="project-invite-form" class="px-4 py-3.5" @submit.prevent="sendInvitation">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-end">
          <div class="flex-1 space-y-1.5">
            <Label for="invite-email">{{ t("project_settings.members.email") }}</Label>
            <Input
              id="invite-email"
              v-model="inviteEmail"
              type="email"
              :placeholder="t('project_settings.members.email_placeholder')"
              maxlength="160"
              required
            />
          </div>
          <div class="space-y-1.5 sm:w-32">
            <Label for="invite-role">{{ t("project_settings.members.role") }}</Label>
            <Select v-model="inviteRole">
              <SelectTrigger id="invite-role" class="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="editor">{{
                  t("project_settings.members.role_editor")
                }}</SelectItem>
                <SelectItem value="viewer">{{
                  t("project_settings.members.role_viewer")
                }}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button type="submit" :disabled="invitationPending">
            <Loader2 v-if="invitationPending" class="size-4 animate-spin" aria-hidden="true" />
            {{ t("project_settings.members.submit") }}
          </Button>
        </div>
      </form>

      <div v-if="pendingInvitations.length > 0" id="project-pending-invitations">
        <div
          class="px-4 pb-1 pt-3 text-xs font-medium uppercase tracking-wide text-muted-foreground"
        >
          {{ t("project_settings.members.pending_title") }}
        </div>
        <div
          v-for="invitation in pendingInvitations"
          :id="`project-pending-invitation-${invitation.id}`"
          :key="invitation.id"
          class="grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3 sm:grid-cols-[minmax(0,1fr)_auto]"
        >
          <div class="min-w-0">
            <div class="truncate font-medium">{{ invitation.email }}</div>
            <div class="flex flex-wrap items-center gap-2 text-[13px] text-muted-foreground">
              <Badge variant="outline">{{ roleLabel(invitation.role) }}</Badge>
              <span class="inline-flex items-center gap-1">
                <Clock3 class="size-3.5" aria-hidden="true" />
                {{
                  t("project_settings.members.expires", {
                    date: formatExpiry(invitation.expires_at),
                  })
                }}
              </span>
            </div>
          </div>
          <div class="flex items-center justify-end">
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
              {{ t("project_settings.members.revoke") }}
            </Button>
          </div>
        </div>
      </div>
    </SettingsSection>

    <SettingsSection :title="t('project_settings.members.members_section')" :hint="memberCount">
      <div
        v-for="member in members"
        :key="member.id"
        :data-testid="`project-member-${member.id}`"
        class="grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3 sm:grid-cols-[minmax(0,1fr)_auto]"
      >
        <div class="flex min-w-0 items-center gap-3">
          <UserAvatar :email="member.email" :display-name="member.display_name" size="sm" />
          <div class="min-w-0">
            <div class="truncate font-medium">{{ memberDisplayName(member) }}</div>
            <div v-if="member.display_name" class="truncate text-[13px] text-muted-foreground">
              {{ member.email }}
            </div>
          </div>
        </div>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <Badge :variant="member.role === 'owner' ? 'default' : 'outline'">
            {{ roleLabel(member.role) }}
          </Badge>
          <Button
            v-if="canTransferOwnership && canActOn(member)"
            :id="`transfer-project-ownership-${member.user_id}`"
            type="button"
            variant="outline"
            size="sm"
            class="gap-1.5"
            @click="requestOwnershipTransfer(member)"
          >
            <Crown class="size-3.5" aria-hidden="true" />
            {{ t("project_settings.members.transfer.action") }}
          </Button>
          <Button
            v-if="canActOn(member)"
            :id="`remove-project-member-${member.id}`"
            type="button"
            variant="ghost"
            size="sm"
            class="text-destructive hover:text-destructive"
            :aria-label="t('project_settings.members.remove.action')"
            @click="requestRemoval(member)"
          >
            <UserMinus class="size-4" aria-hidden="true" />
          </Button>
        </div>
      </div>

      <template #footer>{{ t("project_settings.members.owner_note") }}</template>
    </SettingsSection>

    <ConfirmDialog
      v-model:open="transferDialogOpen"
      :title="t('project_settings.members.transfer.title')"
      :description="
        t('project_settings.members.transfer.description', {
          name: transferTarget ? memberDisplayName(transferTarget) : '',
        })
      "
      :confirm-text="t('project_settings.members.transfer.confirm')"
      :cancel-text="t('project_settings.members.transfer.cancel')"
      :pending="transferPending"
      :pending-text="t('project_settings.members.transfer.pending')"
      :close-on-confirm="false"
      :error="
        transferTransportFailed
          ? t('project_settings.members.transfer.connection_unconfirmed')
          : undefined
      "
      variant="warning"
      :icon="Crown"
      @confirm="transferOwnership"
      @cancel="resetOwnershipTransfer"
    />

    <ConfirmDialog
      v-model:open="removeDialogOpen"
      :title="
        t('project_settings.members.remove.title', {
          name: removeTarget ? memberDisplayName(removeTarget) : '',
        })
      "
      :description="t('project_settings.members.remove.description')"
      :confirm-text="t('project_settings.members.remove.confirm')"
      :cancel-text="t('project_settings.members.remove.cancel')"
      variant="destructive"
      :icon="UserMinus"
      @confirm="confirmRemoval"
    />
  </SettingsPage>
</template>
