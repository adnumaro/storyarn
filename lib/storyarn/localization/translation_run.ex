defmodule Storyarn.Localization.TranslationRun do
  @moduledoc "Persistent state for an asynchronous localization batch."

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project

  @statuses ~w(queued running completed failed cancelled)
  @text_statuses ~w(pending draft in_progress review final)

  schema "localization_translation_runs" do
    field :target_locale, :string
    field :source_type, :string
    field :text_status, :string, default: "pending"
    field :status, :string, default: "queued"
    field :total_count, :integer, default: 0
    field :processed_count, :integer, default: 0
    field :translated_count, :integer, default: 0
    field :failed_count, :integer, default: 0
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :cancelled_at, :utc_datetime
    field :oban_job_id, :integer

    belongs_to :project, Project
    belongs_to :requested_by, User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :target_locale,
      :source_type,
      :text_status,
      :total_count,
      :requested_by_id
    ])
    |> validate_required([:target_locale, :text_status])
    |> validate_length(:target_locale, min: 2, max: 10)
    |> validate_inclusion(:text_status, @text_statuses)
    |> unique_constraint([:project_id, :target_locale],
      name: :localization_translation_runs_one_active,
      message: "already has an active translation run"
    )
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:requested_by_id)
  end

  def update_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :processed_count,
      :translated_count,
      :failed_count,
      :error,
      :started_at,
      :completed_at,
      :cancelled_at,
      :oban_job_id
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:processed_count, greater_than_or_equal_to: 0)
    |> validate_number(:translated_count, greater_than_or_equal_to: 0)
    |> validate_number(:failed_count, greater_than_or_equal_to: 0)
  end
end
