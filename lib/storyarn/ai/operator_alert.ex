defmodule Storyarn.AI.OperatorAlert do
  @moduledoc "Durable, content-free alert requiring Storyarn operator attention."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.AI.Operation
  alias Storyarn.Workspaces.Workspace

  schema "ai_operator_alerts" do
    field :dedupe_key, :string
    field :kind, :string
    field :severity, :string
    field :status, :string, default: "open"
    field :workspace_id_snapshot, :integer
    field :metadata, :map, default: %{}
    field :resolved_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :operation, Operation

    timestamps(type: :utc_datetime)
  end

  def create_changeset(alert, attrs) do
    alert
    |> cast(attrs, [:dedupe_key, :kind, :severity, :status, :workspace_id_snapshot, :metadata])
    |> put_change(:workspace_id, Map.get(attrs, :workspace_id))
    |> put_change(:operation_id, Map.get(attrs, :operation_id))
    |> validate_required([:dedupe_key, :kind, :severity, :status])
    |> validate_inclusion(
      :kind,
      ~w(allowance_anomaly provider_cost_spike unknown_operation stale_reservation duplicate_attempt)
    )
    |> validate_inclusion(:severity, ~w(warning critical))
    |> validate_inclusion(:status, ~w(open resolved))
    |> validate_length(:dedupe_key, min: 1, max: 200)
    |> unique_constraint(:dedupe_key)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:operation_id)
  end
end
