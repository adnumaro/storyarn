defmodule Storyarn.Commercial.Billing.Subscription do
  @moduledoc """
  Schema linking an account to a billing plan. Every workspace the account
  owns takes its limits from this plan.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Commercial.Billing.Persistence.UserRecord, as: User
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
    # The size limits the account exceeds. While any is listed, every
    # workspace the account owns is read-only.
    field :read_only_reasons, {:array, :string}, default: []
    field :read_only_since, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  def create_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:user_id, :plan, :status])
    |> validate_required([:user_id, :plan, :status])
    |> validate_inclusion(:plan, Map.keys(Plan.all()))
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :subscriptions_status_must_be_known)
    |> unique_constraint(:user_id)
  end

  @doc false
  def read_only_changeset(subscription, reasons, now) when is_list(reasons) do
    since = if reasons == [], do: nil, else: subscription.read_only_since || now

    change(subscription, read_only_reasons: reasons, read_only_since: since)
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
