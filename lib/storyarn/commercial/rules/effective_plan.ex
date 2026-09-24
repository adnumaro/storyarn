defmodule Storyarn.Commercial.Billing.EffectivePlan do
  @moduledoc """
  Decides which plan a subscription grants from its status.

  The contracted plan applies while the subscription is in good standing or
  its payment is being retried (`past_due`). Any other status grants the
  default plan. A downgrade only blocks work above the lower limits; nothing
  already stored is deleted.
  """

  alias Storyarn.Commercial.Billing.Plan

  @entitled_statuses ~w(active trialing past_due)

  @spec entitled_statuses() :: [String.t()]
  def entitled_statuses, do: @entitled_statuses

  @spec resolve(String.t(), String.t()) :: String.t()
  def resolve(plan, status) when status in @entitled_statuses, do: plan
  def resolve(_plan, _status), do: Plan.default_plan()
end
