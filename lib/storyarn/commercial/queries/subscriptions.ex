defmodule Storyarn.Commercial.Queries.Subscriptions do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Commercial.Billing.EffectivePlan
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceRecord
  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Repo

  def get_subscription(user_id) do
    Repo.get_by(Subscription, user_id: user_id)
  end

  @doc """
  Returns the plan the account is entitled to, which is the default plan when
  its subscription's status does not grant the contracted one.
  """
  def plan_for_user(user_id) do
    user_id
    |> get_subscription()
    |> effective_plan()
  end

  @doc """
  Returns the plan a workspace takes its limits from: its owner's.
  """
  def plan_for(%{id: _} = workspace) do
    plan_for_workspace_id(workspace.id)
  end

  def plan_for_workspace_id(workspace_id) do
    workspace_id
    |> List.wrap()
    |> owner_subscriptions()
    |> Map.get(workspace_id)
    |> effective_plan()
  end

  @spec plans_for_workspace_ids([pos_integer()]) :: %{pos_integer() => String.t()}
  def plans_for_workspace_ids(workspace_ids) when is_list(workspace_ids) do
    workspace_ids = Enum.uniq(workspace_ids)
    subscriptions = owner_subscriptions(workspace_ids)

    Map.new(workspace_ids, fn workspace_id ->
      {workspace_id, subscriptions |> Map.get(workspace_id) |> effective_plan()}
    end)
  end

  defp owner_subscriptions([]), do: %{}

  defp owner_subscriptions(workspace_ids) do
    from(workspace in WorkspaceRecord,
      join: subscription in Subscription,
      on: subscription.user_id == workspace.owner_id,
      where: workspace.id in ^workspace_ids,
      select: {workspace.id, subscription}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp effective_plan(%Subscription{plan: plan, status: status}), do: EffectivePlan.resolve(plan, status)
  defp effective_plan(nil), do: Plan.default_plan()
end
