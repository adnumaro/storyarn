defmodule Storyarn.Commercial.Billing.Subscription do
  @moduledoc """
  Schema linking a workspace to a billing plan.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Commercial.Billing.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Commercial.Billing.Plan

  # Stripe's subscription statuses. The database enforces the same set.
  @statuses ~w(active trialing past_due incomplete incomplete_expired unpaid canceled paused)

  schema "subscriptions" do
    field :plan, :string, default: "free"
    field :status, :string, default: "active"
    field :payment_provider, :string
    field :external_customer_id, :string
    field :external_subscription_id, :string
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :canceled_at, :utc_datetime

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  def create_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:workspace_id, :plan, :status])
    |> validate_required([:workspace_id, :plan, :status])
    |> validate_inclusion(:plan, Map.keys(Plan.all()))
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :subscriptions_status_must_be_known)
    |> unique_constraint(:workspace_id)
  end

  def update_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :plan,
      :status,
      :payment_provider,
      :external_customer_id,
      :external_subscription_id,
      :current_period_start,
      :current_period_end,
      :canceled_at
    ])
    |> validate_required([:plan, :status])
    |> validate_inclusion(:plan, Map.keys(Plan.all()))
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :subscriptions_status_must_be_known)
  end
end
