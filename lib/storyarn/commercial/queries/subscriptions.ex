defmodule Storyarn.Commercial.Queries.Subscriptions do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Commercial.Billing.EffectivePlan
  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Repo

  def get_subscription(workspace_id) do
    Repo.get_by(Subscription, workspace_id: workspace_id)
  end

  @doc """
  Returns the plan the workspace is entitled to, which is the default plan
  when its subscription's status does not grant the contracted one.
  """
  def plan_for(%{id: _} = workspace) do
    plan_for_workspace_id(workspace.id)
  end

  def plan_for_workspace_id(workspace_id) do
    case get_subscription(workspace_id) do
      %Subscription{plan: plan, status: status} -> EffectivePlan.resolve(plan, status)
      nil -> Plan.default_plan()
    end
  end

  @spec plans_for_workspace_ids([pos_integer()]) :: %{pos_integer() => String.t()}
  def plans_for_workspace_ids(workspace_ids) when is_list(workspace_ids) do
    workspace_ids = Enum.uniq(workspace_ids)

    plans =
      if workspace_ids == [] do
        %{}
      else
        Subscription
        |> where([subscription], subscription.workspace_id in ^workspace_ids)
        |> select([subscription], {subscription.workspace_id, {subscription.plan, subscription.status}})
        |> Repo.all()
        |> Map.new(fn {workspace_id, {plan, status}} ->
          {workspace_id, EffectivePlan.resolve(plan, status)}
        end)
      end

    Map.new(workspace_ids, fn workspace_id ->
      {workspace_id, Map.get(plans, workspace_id, Plan.default_plan())}
    end)
  end
end
