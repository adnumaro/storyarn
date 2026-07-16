defmodule Storyarn.Imports.PlanCleanupRequest do
  @moduledoc """
  Durable, privacy-safe ownership of an encrypted import plan.

  The row is created before object storage is written and survives permanent
  project deletion. It stores no uploaded filename, narrative content, or user
  identifier, so cleanup can be retried without retaining source PII in logs or
  job arguments.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Project

  @states ~w(reserved retained pending deleting completed)
  @formats ~w(yarn storyarn)

  schema "import_plan_cleanup_requests" do
    field :plan_storage_key, :string
    field :format, :string
    field :parser_version, :string
    field :state, :string
    field :cleanup_after, :utc_datetime
    field :attempt_count, :integer, default: 0
    field :generation, :integer, default: 0
    field :last_error_code, :string
    field :completed_at, :utc_datetime

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def reservation_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :plan_storage_key,
      :format,
      :parser_version,
      :state,
      :cleanup_after
    ])
    |> validate_required([:plan_storage_key, :format, :parser_version, :state, :cleanup_after])
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:format, @formats)
    |> validate_length(:plan_storage_key, max: 255)
    |> validate_format(:plan_storage_key, ~r/\Aimports\/plans\/[0-9a-f-]{36}\.plan\.enc\z/)
    |> validate_length(:parser_version, max: 30)
    |> validate_length(:last_error_code, max: 100)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:plan_storage_key)
    |> check_constraint(:state, name: :import_plan_cleanup_requests_state_check)
    |> check_constraint(:format, name: :import_plan_cleanup_requests_format_check)
    |> check_constraint(:state, name: :import_plan_cleanup_requests_state_fields_check)
    |> check_constraint(:attempt_count, name: :import_plan_cleanup_requests_attempt_count_check)
    |> check_constraint(:generation, name: :import_plan_cleanup_requests_generation_check)
  end
end
