defmodule Storyarn.Commercial.Billing.AccountLimits do
  @moduledoc """
  Whether an account is over its plan's size limits, and the read-only state
  that follows.

  An account is over its limits when it exceeds any of: the workspaces it
  owns, the projects in one of them, the items in one of their projects, the
  storage of one of them, or its editor seats. Count limits (backups, named
  versions, templates) never make an account read-only; they only block
  creating more.

  Every creation already checks its limit, so an account can only go over
  when its plan drops. `refresh/1` therefore runs whenever the subscription
  changes, and the account is re-evaluated on every read-only check while it
  is locked, so it unlocks as soon as deletions bring it back within limits.
  The result is stored on the subscription: an unlocked account costs one
  query to check.

  Both lock the owner's subscription row, always after any Workspace, Project
  or user lock the caller holds, and take no other lock while holding it.
  Recording a plan period references the user row, so `refresh/1`, the only
  path that records one, locks that row before the subscription.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Commercial.Billing.EditorSeats
  alias Storyarn.Commercial.Billing.EffectivePlan
  alias Storyarn.Commercial.Billing.Limits
  alias Storyarn.Commercial.Billing.Persistence.ProjectRecord, as: Project
  alias Storyarn.Commercial.Billing.Persistence.UserRecord
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.PlanPeriod
  alias Storyarn.Commercial.Billing.StorageAccounting
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Commercial.Queries.Subscriptions
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @doc """
  Returns the size limits the account exceeds, in a fixed order.
  """
  @spec exceeded(pos_integer()) :: [atom()]
  def exceeded(user_id) do
    plan = Subscriptions.plan_for_user(user_id)
    workspace_ids = owned_workspace_ids(user_id)

    [
      workspaces_per_user: fn limit -> length(workspace_ids) > limit end,
      projects_per_workspace: fn limit -> Enum.any?(project_counts(workspace_ids), &(&1 > limit)) end,
      items_per_project: fn limit ->
        workspace_ids |> project_ids() |> Enum.any?(&(Limits.count_project_items(&1) > limit))
      end,
      storage_bytes_per_workspace: fn limit ->
        Enum.any?(workspace_ids, &(StorageAccounting.workspace_usage(&1).accounted_bytes > limit))
      end,
      editors_per_account: fn limit -> EditorSeats.usage(user_id).used > limit end
    ]
    |> Enum.filter(fn {resource, over?} -> over_limit?(Plan.limit(plan, resource), over?) end)
    |> Enum.map(fn {resource, _over?} -> resource end)
  end

  @doc """
  Re-evaluates the account and stores the result on its subscription. Also
  records a new plan period when the effective plan changed.

  Returns the limits the account exceeds, as strings; empty when it is
  within them.
  """
  @spec refresh(pos_integer()) :: {:ok, [String.t()]}
  def refresh(user_id) do
    Repo.transact(fn ->
      lock_account_holder(user_id)
      evaluate(user_id, :record_plan_period)
    end)
  end

  @doc """
  Locks the account holder's user row for key share: what inserting a plan
  period needs, taken before the subscription row so that no chain reaches the
  two in the opposite order.
  """
  @spec lock_account_holder(pos_integer()) :: :ok
  def lock_account_holder(user_id) do
    Repo.all(from(user in UserRecord, where: user.id == ^user_id, select: user.id, lock: "FOR KEY SHARE"))
    :ok
  end

  defp evaluate(user_id, plan_period) do
    Repo.transact(fn ->
      case lock_subscription(user_id) do
        nil ->
          {:ok, []}

        %Subscription{} = subscription ->
          now = TimeHelpers.now()
          :ok = record_plan_period(subscription, now, plan_period)
          reasons = user_id |> exceeded() |> Enum.map(&Atom.to_string/1)

          subscription
          |> Subscription.read_only_changeset(reasons, now)
          |> Repo.update!()

          {:ok, reasons}
      end
    end)
  end

  @doc """
  Returns why the workspace is read-only: the limits its owner's account
  exceeds, empty when it is writable. A locked account is re-evaluated first,
  so the answer turns empty as soon as it is back within limits.
  """
  @spec workspace_read_only_reasons(pos_integer()) :: [String.t()]
  def workspace_read_only_reasons(workspace_id) when is_integer(workspace_id) do
    from(workspace in Workspace,
      join: subscription in Subscription,
      on: subscription.user_id == workspace.owner_id,
      where: workspace.id == ^workspace_id,
      select: {workspace.owner_id, subscription.read_only_reasons}
    )
    |> Repo.one()
    |> current_reasons()
  end

  @doc "Same as `workspace_read_only_reasons/1`, for an account."
  @spec account_read_only_reasons(pos_integer()) :: [String.t()]
  def account_read_only_reasons(user_id) when is_integer(user_id) do
    from(subscription in Subscription,
      where: subscription.user_id == ^user_id,
      select: {subscription.user_id, subscription.read_only_reasons}
    )
    |> Repo.one()
    |> current_reasons()
  end

  defp current_reasons({_owner_id, []}), do: []

  defp current_reasons({owner_id, _stored_reasons}) do
    {:ok, reasons} = evaluate(owner_id, :keep_plan_periods)
    reasons
  end

  defp current_reasons(nil), do: []

  defp over_limit?(limit, over?) when is_integer(limit), do: over?.(limit)
  # A resource the plan does not define is blocked, as everywhere else.
  defp over_limit?(nil, over?), do: over?.(0)
  # :unlimited, and :paid_seats, which ENG-231 enforces per paid seat.
  defp over_limit?(_unbounded, _over?), do: false

  defp owned_workspace_ids(user_id) do
    Repo.all(from(workspace in Workspace, where: workspace.owner_id == ^user_id, select: workspace.id))
  end

  defp project_counts([]), do: []

  defp project_counts(workspace_ids) do
    Repo.all(
      from(project in Project,
        where: project.workspace_id in ^workspace_ids and is_nil(project.deleted_at),
        group_by: project.workspace_id,
        select: count(project.id)
      )
    )
  end

  defp project_ids([]), do: []

  defp project_ids(workspace_ids) do
    Repo.all(
      from(project in Project,
        where: project.workspace_id in ^workspace_ids and is_nil(project.deleted_at),
        select: project.id
      )
    )
  end

  defp lock_subscription(user_id) do
    Repo.one(from(subscription in Subscription, where: subscription.user_id == ^user_id, lock: "FOR UPDATE"))
  end

  defp record_plan_period(_subscription, _now, :keep_plan_periods), do: :ok

  defp record_plan_period(%Subscription{user_id: user_id, plan: plan, status: status}, now, :record_plan_period) do
    effective_plan = EffectivePlan.resolve(plan, status)

    latest_plan =
      Repo.one(
        from(period in PlanPeriod,
          where: period.user_id == ^user_id,
          order_by: [desc: period.started_at],
          limit: 1,
          select: period.plan
        )
      )

    if latest_plan != effective_plan do
      Repo.insert!(%PlanPeriod{user_id: user_id, plan: effective_plan, started_at: now},
        on_conflict: {:replace, [:plan]},
        conflict_target: [:user_id, :started_at]
      )
    end

    :ok
  end
end
