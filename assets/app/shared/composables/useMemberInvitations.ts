import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { useLive } from "./useLive";

export function useMemberInvitations(defaultRole: string) {
  const live = useLive();
  const { locale } = useI18n({ useScope: "global" });

  const inviteEmail = ref("");
  const inviteRole = ref(defaultRole);
  const invitationPending = ref(false);
  const revokingInvitationId = ref<number | null>(null);

  live.handleEvent("invitation_sent", () => {
    inviteEmail.value = "";
    inviteRole.value = defaultRole;
  });

  function sendInvitation() {
    if (invitationPending.value) return;

    invitationPending.value = true;
    const complete = () => (invitationPending.value = false);

    live.pushEvent(
      "send_invitation",
      {
        invite: {
          email: inviteEmail.value,
          role: inviteRole.value,
        },
      },
      complete,
      complete,
    );
  }

  function revokeInvitation(id: number) {
    if (revokingInvitationId.value !== null) return;

    revokingInvitationId.value = id;
    const complete = () => (revokingInvitationId.value = null);

    live.pushEvent("revoke_invitation", { id: String(id) }, complete, complete);
  }

  function formatExpiry(expiresAt: string) {
    return new Intl.DateTimeFormat(locale.value, { dateStyle: "medium" }).format(
      new Date(expiresAt),
    );
  }

  return {
    live,
    inviteEmail,
    inviteRole,
    invitationPending,
    revokingInvitationId,
    sendInvitation,
    revokeInvitation,
    formatExpiry,
  };
}
