defmodule Storyarn.Commercial.Commands.Subscriptions do
  @moduledoc false

  alias Storyarn.Commercial.Billing.EffectivePlan
  alias Storyarn.Commercial.Billing.PlanPeriod
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  # The account's first plan period starts with its subscription, so the trash
  # always finds the plan an item was deleted under.
  def create_subscription(%{id: _} = user, plan) do
    Repo.transact(fn ->
      with {:ok, %Subscription{} = subscription} <-
             %Subscription{}
             |> Subscription.create_changeset(%{user_id: user.id, plan: plan, status: "active"})
             |> Repo.insert() do
        Repo.insert!(%PlanPeriod{
          user_id: subscription.user_id,
          plan: EffectivePlan.resolve(subscription.plan, subscription.status),
          started_at: TimeHelpers.now()
        })

        {:ok, subscription}
      end
    end)
  end

  def update_plan(%Subscription{} = subscription, new_plan) do
    subscription
    |> Subscription.update_changeset(%{plan: new_plan})
    |> Repo.update()
  end
end
