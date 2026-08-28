defmodule Storyarn.Platform.Commercial.Queries.Subscriptions do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Billing.Plan
  alias Storyarn.Platform.Billing.Subscription
  alias Storyarn.Repo

  def get_subscription(workspace_id) do
    Repo.get_by(Subscription, workspace_id: workspace_id)
  end

  def plan_for(%{id: _} = workspace) do
    plan_for_workspace_id(workspace.id)
  end

  def plan_for_workspace_id(workspace_id) do
    case get_subscription(workspace_id) do
      %Subscription{plan: plan} -> plan
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
        |> select([subscription], {subscription.workspace_id, subscription.plan})
        |> Repo.all()
        |> Map.new()
      end

    Map.new(workspace_ids, fn workspace_id ->
      {workspace_id, Map.get(plans, workspace_id, Plan.default_plan())}
    end)
  end
end
