defmodule Storyarn.Commercial.Billing.PlanPeriod do
  @moduledoc """
  The effective plan an account had from `started_at` until its next period.

  A new period starts whenever the effective plan changes. The trash uses it
  to keep the retention an item was granted when it was deleted.
  """

  use Ecto.Schema

  schema "account_plan_periods" do
    field :user_id, :id
    field :plan, :string
    field :started_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
