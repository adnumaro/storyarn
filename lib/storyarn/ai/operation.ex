defmodule Storyarn.AI.Operation do
  @moduledoc "Durable actor intent and AI execution lifecycle."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Context.PersistenceContract
  alias Storyarn.AI.RouteOption
  alias Storyarn.Projects.Project
  alias Storyarn.Workspaces.Workspace

  @execution_statuses ~w(queued running succeeded failed cancelled unknown)
  @dispositions ~w(accepted dismissed abandoned)
  @settlement_statuses ~w(not_applicable reserved committed released)

  @type execution_status :: String.t()
  @type user_disposition :: String.t() | nil
  @type t :: %__MODULE__{}

  schema "ai_operations" do
    field :actor_id, :integer
    field :workspace_id_snapshot, :integer
    field :project_id_snapshot, :integer
    field :task_id, :string
    field :task_contract_hash, :string
    field :capability, :string
    field :idempotency_key, :string
    field :execution_status, :string
    field :user_disposition, :string
    field :settlement_status, :string, default: "not_applicable"
    field :subject_type, :string
    field :subject_id, :integer
    field :subject_revision, :string
    field :context_hash, :string
    field :context_manifest, :map
    field :context_subject, :map
    field :input_hash, :string
    field :input_schema_version, :string
    field :output_schema_version, :string
    field :prompt_version, :string
    field :context_version, :string
    field :result_type, :string
    field :result_destination, :map
    field :policy_decision, :map
    field :execution_route, :map
    field :error_classification, :string
    field :cancellation_requested_at, :utc_datetime
    field :started_at, :utc_datetime
    field :external_attempt_started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :project, Project
    belongs_to :route_option, RouteOption

    timestamps(type: :utc_datetime)
  end

  def create_changeset(operation, attrs) do
    operation
    |> cast(attrs, [
      :task_id,
      :task_contract_hash,
      :capability,
      :idempotency_key,
      :execution_status,
      :settlement_status,
      :subject_type,
      :subject_id,
      :subject_revision,
      :context_hash,
      :context_manifest,
      :context_subject,
      :input_hash,
      :input_schema_version,
      :output_schema_version,
      :prompt_version,
      :context_version,
      :result_type,
      :result_destination,
      :policy_decision,
      :execution_route
    ])
    |> put_identity_fields(attrs)
    |> validate_required([
      :user_id,
      :actor_id,
      :workspace_id,
      :workspace_id_snapshot,
      :route_option_id,
      :task_id,
      :task_contract_hash,
      :capability,
      :idempotency_key,
      :execution_status,
      :settlement_status,
      :input_hash,
      :input_schema_version,
      :output_schema_version,
      :prompt_version,
      :context_version,
      :result_type,
      :result_destination,
      :policy_decision,
      :execution_route
    ])
    |> validate_inclusion(:execution_status, @execution_statuses)
    |> validate_inclusion(:settlement_status, @settlement_statuses)
    |> validate_length(:idempotency_key, min: 1, max: 64)
    |> validate_subject()
    |> validate_context()
    |> check_constraint(:context_hash, name: :ai_operations_context_complete)
    |> unique_constraint([:actor_id, :task_id, :idempotency_key],
      name: :ai_operations_actor_task_idempotency_unique
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:route_option_id)
  end

  def transition_changeset(operation, attrs) do
    operation
    |> cast(attrs, [
      :execution_status,
      :settlement_status,
      :error_classification,
      :cancellation_requested_at,
      :started_at,
      :external_attempt_started_at,
      :completed_at
    ])
    |> validate_required([:execution_status, :settlement_status])
    |> validate_inclusion(:execution_status, @execution_statuses)
    |> validate_inclusion(:settlement_status, @settlement_statuses)
  end

  def disposition_changeset(operation, disposition) when disposition in @dispositions do
    operation
    |> change(user_disposition: disposition)
    |> validate_inclusion(:user_disposition, @dispositions)
    |> validate_change(:user_disposition, fn :user_disposition, _value ->
      if operation.execution_status == "succeeded", do: [], else: [user_disposition: "requires a successful result"]
    end)
  end

  def execution_statuses, do: @execution_statuses
  def dispositions, do: @dispositions

  defp validate_subject(changeset) do
    values = Enum.map([:subject_type, :subject_id, :subject_revision], &get_field(changeset, &1))

    if Enum.all?(values, &is_nil/1) or Enum.all?(values, &(not is_nil(&1))) do
      changeset
    else
      add_error(changeset, :subject_type, "must include type, id, and revision together")
    end
  end

  defp validate_context(changeset) do
    hash = get_field(changeset, :context_hash)
    manifest = get_field(changeset, :context_manifest)
    subject = get_field(changeset, :context_subject)

    if PersistenceContract.valid?(hash, manifest, subject) do
      changeset
    else
      add_error(
        changeset,
        :context_hash,
        "must include hash, manifest, and a scope-compatible subject together"
      )
    end
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce(
      [:user_id, :actor_id, :workspace_id, :workspace_id_snapshot, :project_id, :project_id_snapshot, :route_option_id],
      changeset,
      fn field, acc -> put_change(acc, field, Map.get(attrs, field)) end
    )
  end
end
