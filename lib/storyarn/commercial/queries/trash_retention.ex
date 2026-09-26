defmodule Storyarn.Commercial.Queries.TrashRetention do
  @moduledoc """
  How long a deleted item stays in the trash.

  An item keeps the retention its workspace owner's plan granted when it was
  deleted: a later downgrade never shortens it, and an upgrade lengthens it.
  Its retention is therefore the longer of the plan's at deletion and the
  current plan's.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Commercial.Billing.Persistence.WorkspaceRecord
  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.PlanPeriod
  alias Storyarn.Commercial.Queries.Subscriptions
  alias Storyarn.Repo

  @doc """
  Returns the retention hours of each `{workspace_id, deleted_at}` deletion,
  in the same order.
  """
  @spec hours([{pos_integer(), DateTime.t()}]) :: [pos_integer()]
  def hours([]), do: []

  def hours(deletions) when is_list(deletions) do
    workspace_ids = deletions |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    owners = owners(workspace_ids)
    current_plans = Subscriptions.plans_for_workspace_ids(workspace_ids)
    periods = owners |> Map.values() |> Enum.uniq() |> periods()

    Enum.map(deletions, fn {workspace_id, deleted_at} ->
      current_plan = Map.fetch!(current_plans, workspace_id)
      plan_at_deletion = owners |> Map.get(workspace_id) |> then(&Map.get(periods, &1, [])) |> plan_at(deleted_at)

      max(Plan.retention_hours(plan_at_deletion || current_plan), Plan.retention_hours(current_plan))
    end)
  end

  defp owners(workspace_ids) do
    from(workspace in WorkspaceRecord,
      where: workspace.id in ^workspace_ids,
      select: {workspace.id, workspace.owner_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp periods(user_ids) do
    from(period in PlanPeriod,
      where: period.user_id in ^user_ids,
      order_by: [asc: period.user_id, asc: period.started_at],
      select: {period.user_id, period.started_at, period.plan}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_user_id, started_at, plan} -> {started_at, plan} end)
  end

  # The plan of the last period that started before the deletion; nil when
  # the deletion predates every recorded period.
  defp plan_at(periods, deleted_at) do
    Enum.reduce_while(periods, nil, fn {started_at, plan}, plan_so_far ->
      if DateTime.after?(started_at, deleted_at),
        do: {:halt, plan_so_far},
        else: {:cont, plan}
    end)
  end
end
