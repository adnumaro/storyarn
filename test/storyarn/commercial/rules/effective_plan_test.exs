defmodule Storyarn.Commercial.Billing.EffectivePlanTest do
  use ExUnit.Case, async: true

  alias Storyarn.Commercial.Billing.EffectivePlan
  alias Storyarn.Commercial.Billing.Subscription

  test "the contracted plan applies while the subscription is active, trialing or past due" do
    for status <- ~w(active trialing past_due) do
      assert EffectivePlan.resolve("pro", status) == "pro"
    end
  end

  test "every other status falls back to the default plan" do
    for status <- ~w(incomplete incomplete_expired unpaid canceled paused) do
      assert EffectivePlan.resolve("pro", status) == "free"
    end
  end

  test "every entitled status is a status a subscription can hold" do
    assert EffectivePlan.entitled_statuses() -- Subscription.statuses() == []
  end
end
