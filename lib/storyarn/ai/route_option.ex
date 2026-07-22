defmodule Storyarn.AI.RouteOption do
  @moduledoc "Short-lived, actor-bound execution route selected during preflight."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Operation
  alias Storyarn.Projects.Project
  alias Storyarn.Workspaces.Workspace

  @derive {Inspect, except: [:token_hash, :credential_ref]}

  schema "ai_route_options" do
    field :token_hash, :binary, redact: true
    field :actor_id, :integer
    field :task_id, :string
    field :input_hash, :string
    field :subject_type, :string
    field :subject_id, :integer
    field :subject_revision, :string
    field :lane, :string
    field :provider, :string
    field :model, :string
    field :credential_ref, :map, redact: true
    field :payer, :string
    field :assignment_source, :string
    field :consent_basis, :string
    field :policy_version, :integer
    field :price_id, :string
    field :price_version, :integer
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :project, Project
    belongs_to :consumed_by_operation, Operation

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def issue_changeset(option, attrs) do
    option
    |> cast(attrs, [
      :token_hash,
      :task_id,
      :input_hash,
      :subject_type,
      :subject_id,
      :subject_revision,
      :lane,
      :provider,
      :model,
      :credential_ref,
      :payer,
      :assignment_source,
      :consent_basis,
      :policy_version,
      :price_id,
      :price_version,
      :expires_at
    ])
    |> put_identity_fields(attrs)
    |> validate_required([
      :token_hash,
      :user_id,
      :actor_id,
      :workspace_id,
      :task_id,
      :input_hash,
      :lane,
      :provider,
      :model,
      :credential_ref,
      :payer,
      :assignment_source,
      :consent_basis,
      :policy_version,
      :expires_at
    ])
    |> validate_inclusion(:lane, ~w(managed personal_byok workspace_byok))
    |> validate_number(:policy_version, greater_than: 0)
    |> validate_subject()
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
  end

  def consume_changeset(option, operation_id, consumed_at) do
    option
    |> change(consumed_by_operation_id: operation_id, consumed_at: consumed_at)
    |> validate_required([:consumed_by_operation_id, :consumed_at])
    |> unique_constraint(:consumed_by_operation_id)
    |> foreign_key_constraint(:consumed_by_operation_id)
  end

  defp validate_subject(changeset) do
    values = Enum.map([:subject_type, :subject_id, :subject_revision], &get_field(changeset, &1))

    if Enum.all?(values, &is_nil/1) or Enum.all?(values, &(not is_nil(&1))) do
      changeset
    else
      add_error(changeset, :subject_type, "must include type, id, and revision together")
    end
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce([:user_id, :actor_id, :workspace_id, :project_id], changeset, fn field, acc ->
      put_change(acc, field, Map.get(attrs, field))
    end)
  end
end
