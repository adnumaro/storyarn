defmodule Storyarn.Repo.Migrations.RestrictSubscriptionStatuses do
  use Ecto.Migration

  @moduledoc """
  Restricts `subscriptions.status` to Stripe's subscription statuses. The
  status decides which plan a workspace is entitled to, so an unknown value
  must not reach it.
  """

  def change do
    create constraint(:subscriptions, :subscriptions_status_must_be_known,
             check:
               "status IN ('active', 'trialing', 'past_due', 'incomplete', " <>
                 "'incomplete_expired', 'unpaid', 'canceled', 'paused')"
           )
  end
end
