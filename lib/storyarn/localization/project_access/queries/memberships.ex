defmodule Storyarn.Localization.ProjectAccess.Queries.Memberships do
  @moduledoc false

  alias Storyarn.Localization.ProjectAccess.Projections.ProjectMembershipRecord
  alias Storyarn.Localization.ProjectAccess.Projections.WorkspaceMembershipRecord
  alias Storyarn.Localization.ProjectAccess.Rules.EffectiveMembership
  alias Storyarn.Repo

  @spec get_effective(integer(), integer(), integer()) :: ProjectMembershipRecord.t() | nil
  def get_effective(project_id, user_id, workspace_id)
      when is_integer(project_id) and is_integer(user_id) and is_integer(workspace_id) do
    case Repo.get_by(ProjectMembershipRecord, project_id: project_id, user_id: user_id) do
      %ProjectMembershipRecord{} = membership ->
        membership

      nil ->
        workspace_membership(project_id, user_id, workspace_id)
    end
  end

  defp workspace_membership(project_id, user_id, workspace_id) do
    case Repo.get_by(WorkspaceMembershipRecord, workspace_id: workspace_id, user_id: user_id) do
      %WorkspaceMembershipRecord{role: workspace_role} ->
        %ProjectMembershipRecord{
          project_id: project_id,
          user_id: user_id,
          role: EffectiveMembership.project_role(workspace_role)
        }

      nil ->
        nil
    end
  end
end
