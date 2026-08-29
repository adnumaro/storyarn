defmodule Storyarn.Commercial.Commands.Subscriptions do
  @moduledoc false

  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Repo

  def create_subscription(%{id: _} = workspace, plan) do
    %Subscription{}
    |> Subscription.create_changeset(%{workspace_id: workspace.id, plan: plan, status: "active"})
    |> Repo.insert()
  end

  def update_plan(%Subscription{} = subscription, new_plan) do
    subscription
    |> Subscription.update_changeset(%{plan: new_plan})
    |> Repo.update()
  end
end
