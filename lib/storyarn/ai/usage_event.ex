defmodule Storyarn.AI.UsageEvent do
  @moduledoc "Content-free record for the single external attempt of an operation."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.AI.Operation

  @statuses ~w(running succeeded failed unknown)

  schema "ai_usage_events" do
    field :status, :string
    field :lane, :string
    field :provider, :string
    field :model, :string
    field :provider_request_id, :string
    field :input_units, :integer
    field :output_units, :integer
    field :latency_ms, :integer
    field :provider_cost, :decimal
    field :provider_cost_currency, :string
    field :error_classification, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :operation, Operation

    timestamps(type: :utc_datetime)
  end

  def start_changeset(event, attrs) do
    event
    |> cast(attrs, [:status, :lane, :provider, :model, :started_at])
    |> put_change(:operation_id, Map.get(attrs, :operation_id))
    |> validate_required([:operation_id, :status, :lane, :provider, :model, :started_at])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:operation_id)
    |> foreign_key_constraint(:operation_id)
  end

  def finish_changeset(event, attrs) do
    event
    |> cast(attrs, [
      :status,
      :provider_request_id,
      :input_units,
      :output_units,
      :latency_ms,
      :provider_cost,
      :provider_cost_currency,
      :error_classification,
      :completed_at
    ])
    |> validate_required([:status, :completed_at])
    |> validate_inclusion(:status, @statuses -- ["running"])
    |> validate_number(:input_units, greater_than_or_equal_to: 0)
    |> validate_number(:output_units, greater_than_or_equal_to: 0)
    |> validate_number(:latency_ms, greater_than_or_equal_to: 0)
    |> validate_number(:provider_cost, greater_than_or_equal_to: 0)
  end
end
