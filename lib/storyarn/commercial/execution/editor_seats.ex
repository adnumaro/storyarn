defmodule Storyarn.Commercial.Billing.EditorSeats do
  @moduledoc """
  Editor seats of an account.

  A seat is a distinct person, by email, with an editing role in any workspace
  the account owns: workspace owner, admin or member, or project owner or
  editor. Each person counts once however many workspaces or projects they
  edit, the owner counts, and viewers are free. A pending editor invitation
  holds its seat until it is accepted, expires or is revoked.

  Only the account owner can raise the count. Anyone else may invite viewers
  or give an editing role to someone who already holds a seat. An operator
  acting from the release tasks is treated like the owner.

  Every check locks the owner's subscription row, so two admissions for the
  same account, even in different workspaces, cannot both take the last seat.
  Callers must run the check inside the transaction that writes the
  membership or invitation. Nothing else locks subscription rows, so this lock
  cannot close a cycle with the Workspace or Project locks callers already
  hold.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Commercial.Billing.Persistence.ProjectInvitationRecord, as: ProjectInvitation
  alias Storyarn.Commercial.Billing.Persistence.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.Commercial.Billing.Persistence.ProjectRecord, as: Project
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceInvitationRecord, as: WorkspaceInvitation
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Commercial.Queries.Subscriptions
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @workspace_editing_roles ~w(owner admin member)
  @project_editing_roles ~w(owner editor)

  @type actor :: pos_integer() | :operator
  @type result ::
          :ok
          | {:error, :limit_reached, %{resource: :editors_per_account, used: non_neg_integer(), limit: term()}}
          | {:error, :seat_requires_account_owner}

  @doc """
  Checks that giving `role` to `email` in a workspace or project fits the
  account's seats, for an invitation, a role change or a project transfer.
  """
  @spec check(map(), String.t(), String.t(), actor()) :: result()
  def check(parent, email, role, actor) when is_binary(email) and is_binary(role) do
    if editing_role?(parent, role) do
      owner_id = owner_id(parent)
      lock_account(owner_id)
      email = normalize(email)

      cond do
        seat_held?(owner_id, email, :with_invitations) -> :ok
        actor in [owner_id, :operator] -> within_limit(owner_id, :with_invitations)
        true -> {:error, :seat_requires_account_owner}
      end
    else
      :ok
    end
  end

  @doc """
  Checks that accepting an editor invitation fits the account's seats.

  Only memberships count: the invitation being accepted already holds its
  seat. This protects invitations created before the account moved to a
  smaller plan.
  """
  @spec check_acceptance(map(), String.t(), String.t()) :: result()
  def check_acceptance(parent, email, role) when is_binary(email) and is_binary(role) do
    if editing_role?(parent, role) do
      owner_id = owner_id(parent)
      lock_account(owner_id)

      if seat_held?(owner_id, normalize(email), :members_only),
        do: :ok,
        else: within_limit(owner_id, :members_only)
    else
      :ok
    end
  end

  @doc """
  Returns the seats an account uses, pending editor invitations included, and
  its plan's editor limit.
  """
  @spec usage(pos_integer()) :: %{used: non_neg_integer(), limit: term()}
  def usage(owner_id) do
    %{used: count(owner_id, :with_invitations), limit: limit(owner_id)}
  end

  defp editing_role?(%{workspace_id: _}, role), do: role in @project_editing_roles
  defp editing_role?(%{id: _}, role), do: role in @workspace_editing_roles

  defp owner_id(parent) do
    workspace_id = Map.get(parent, :workspace_id) || Map.fetch!(parent, :id)
    Repo.one!(from(workspace in Workspace, where: workspace.id == ^workspace_id, select: workspace.owner_id))
  end

  defp lock_account(owner_id) do
    Repo.all(
      from(subscription in Subscription,
        where: subscription.user_id == ^owner_id,
        select: subscription.id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp within_limit(owner_id, scope) do
    limit = limit(owner_id)
    used = count(owner_id, scope)

    case limit do
      # Paid seats are bought one by one; ENG-231 adds and removes them.
      :paid_seats -> :ok
      :unlimited -> :ok
      limit when is_integer(limit) and used < limit -> :ok
      limit -> {:error, :limit_reached, %{resource: :editors_per_account, used: used, limit: limit || 0}}
    end
  end

  defp limit(owner_id) do
    owner_id
    |> Subscriptions.plan_for_user()
    |> Plan.limit(:editors_per_account)
  end

  defp count(owner_id, scope) do
    Repo.one(from(seat in subquery(seats_query(owner_id, scope)), select: count(seat.email)))
  end

  defp seat_held?(owner_id, email, scope) do
    Repo.exists?(from(seat in subquery(seats_query(owner_id, scope)), where: seat.email == ^email))
  end

  defp seats_query(owner_id, :members_only) do
    workspace_editors =
      from(membership in WorkspaceMembership,
        join: workspace in Workspace,
        on: workspace.id == membership.workspace_id,
        join: user in assoc(membership, :user),
        where: workspace.owner_id == ^owner_id,
        where: membership.role in ^@workspace_editing_roles,
        select: %{email: fragment("lower(?)", user.email)}
      )

    project_editors =
      from(membership in ProjectMembership,
        join: project in Project,
        on: project.id == membership.project_id,
        join: workspace in Workspace,
        on: workspace.id == project.workspace_id,
        join: user in assoc(membership, :user),
        where: workspace.owner_id == ^owner_id and is_nil(project.deleted_at),
        where: membership.role in ^@project_editing_roles,
        select: %{email: fragment("lower(?)", user.email)}
      )

    union(workspace_editors, ^project_editors)
  end

  defp seats_query(owner_id, :with_invitations) do
    now = TimeHelpers.now()

    workspace_invitations =
      from(invitation in WorkspaceInvitation,
        join: workspace in Workspace,
        on: workspace.id == invitation.workspace_id,
        where: workspace.owner_id == ^owner_id,
        where: invitation.role in ^@workspace_editing_roles,
        where: is_nil(invitation.accepted_at) and invitation.expires_at > ^now,
        select: %{email: fragment("lower(?)", invitation.email)}
      )

    project_invitations =
      from(invitation in ProjectInvitation,
        join: project in Project,
        on: project.id == invitation.project_id,
        join: workspace in Workspace,
        on: workspace.id == project.workspace_id,
        where: workspace.owner_id == ^owner_id and is_nil(project.deleted_at),
        where: invitation.role in ^@project_editing_roles,
        where: is_nil(invitation.accepted_at) and invitation.expires_at > ^now,
        select: %{email: fragment("lower(?)", invitation.email)}
      )

    owner_id
    |> seats_query(:members_only)
    |> union(^workspace_invitations)
    |> union(^project_invitations)
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
