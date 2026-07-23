defmodule Storyarn.Repo.Migrations.InvalidatePersonalAiOnWorkspaceMembershipRemoval do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM ai_personal_preferences AS preference
     WHERE NOT EXISTS (
       SELECT 1
         FROM workspace_memberships AS membership
        WHERE membership.user_id = preference.user_id
          AND membership.workspace_id = preference.workspace_id
     )
    """

    execute """
    DELETE FROM ai_personal_consents AS consent
     WHERE NOT EXISTS (
       SELECT 1
         FROM workspace_memberships AS membership
        WHERE membership.user_id = consent.user_id
          AND membership.workspace_id = consent.workspace_id
     )
    """

    execute """
    DELETE FROM ai_integration_workspace_assignments AS assignment
     WHERE NOT EXISTS (
       SELECT 1
         FROM workspace_memberships AS membership
        WHERE membership.user_id = assignment.user_id
          AND membership.workspace_id = assignment.workspace_id
     )
    """

    execute """
    ALTER TABLE ai_integration_workspace_assignments
    ADD CONSTRAINT ai_assignments_workspace_membership_fkey
    FOREIGN KEY (workspace_id, user_id)
    REFERENCES workspace_memberships(workspace_id, user_id)
    ON DELETE CASCADE
    """

    execute """
    ALTER TABLE ai_personal_consents
    ADD CONSTRAINT ai_personal_consents_workspace_membership_fkey
    FOREIGN KEY (workspace_id, user_id)
    REFERENCES workspace_memberships(workspace_id, user_id)
    ON DELETE CASCADE
    """

    execute """
    ALTER TABLE ai_personal_preferences
    ADD CONSTRAINT ai_personal_preferences_workspace_membership_fkey
    FOREIGN KEY (workspace_id, user_id)
    REFERENCES workspace_memberships(workspace_id, user_id)
    ON DELETE CASCADE
    """
  end

  def down do
    execute """
    ALTER TABLE ai_personal_preferences
    DROP CONSTRAINT ai_personal_preferences_workspace_membership_fkey
    """

    execute """
    ALTER TABLE ai_personal_consents
    DROP CONSTRAINT ai_personal_consents_workspace_membership_fkey
    """

    execute """
    ALTER TABLE ai_integration_workspace_assignments
    DROP CONSTRAINT ai_assignments_workspace_membership_fkey
    """
  end
end
