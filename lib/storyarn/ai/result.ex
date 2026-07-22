defmodule Storyarn.AI.Result do
  @moduledoc "Actor-private encrypted input and temporary structured output."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Operation
  alias Storyarn.Projects.Project
  alias Storyarn.Shared.EncryptedBinary
  alias Storyarn.Workspaces.Workspace

  @derive {Inspect, except: [:input_encrypted, :output_encrypted]}

  schema "ai_results" do
    field :actor_id, :integer
    field :input_encrypted, EncryptedBinary, redact: true
    field :output_encrypted, EncryptedBinary, redact: true
    field :input_hash, :string
    field :task_id, :string
    field :prompt_version, :string
    field :context_version, :string
    field :output_schema_version, :string
    field :expires_at, :utc_datetime

    belongs_to :operation, Operation
    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :project, Project

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(result, attrs) do
    result
    |> cast(attrs, [
      :input_encrypted,
      :input_hash,
      :task_id,
      :prompt_version,
      :context_version,
      :output_schema_version
    ])
    |> put_identity_fields(attrs)
    |> validate_required([
      :operation_id,
      :user_id,
      :actor_id,
      :workspace_id,
      :input_encrypted,
      :input_hash,
      :task_id,
      :prompt_version,
      :context_version,
      :output_schema_version
    ])
    |> unique_constraint(:operation_id)
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
  end

  def output_changeset(result, output, expires_at) when is_binary(output) and not is_nil(expires_at) do
    result
    |> change(output_encrypted: output, expires_at: expires_at)
    |> validate_required([:output_encrypted, :expires_at])
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce([:operation_id, :user_id, :actor_id, :workspace_id, :project_id], changeset, fn field, acc ->
      put_change(acc, field, Map.get(attrs, field))
    end)
  end
end
