defmodule Storyarn.Flows.FindingDismissal do
  @moduledoc """
  Schema for `flow_finding_dismissals` — the single persisted manual
  disposition of structural-analysis findings.

  A row with `restored_at IS NULL` is an ACTIVE dismissal: it suppresses
  exactly the finding occurrence identified by
  `finding_key + rule_version + evidence_fingerprint`. A changed rule
  version or changed evidence reactivates the finding automatically because
  the tuple no longer matches. Restore stamps `restored_at` (history is
  kept); a later re-dismissal inserts a new row. Concurrency is settled by
  the partial unique index `flow_finding_dismissals_active_idx`.

  The optional bounded note is project data: it follows project
  authorization and never enters analytics, logs, or AI prompts. A note is
  required only for the `other` reason code (DB check + changeset).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User

  @reason_codes ~w(intentional_design rule_not_applicable missing_context incorrect_detection duplicate_finding other)
  @max_note_length 2000

  @type t :: %__MODULE__{}

  schema "flow_finding_dismissals" do
    field :finding_key, :string
    field :rule_id, :string
    field :rule_version, :integer
    field :evidence_fingerprint, :string

    field :reason_code, :string
    field :note, :string

    field :restored_at, :utc_datetime

    belongs_to :project, Storyarn.Projects.Project
    belongs_to :flow, Storyarn.Flows.Flow
    belongs_to :dismissed_by, User
    belongs_to :restored_by, User

    timestamps(type: :utc_datetime)
  end

  @doc "Stable internal reason codes, in display order. Labels live in i18n."
  @spec reason_codes() :: [String.t()]
  def reason_codes, do: @reason_codes

  @doc "Maximum accepted note length."
  @spec max_note_length() :: pos_integer()
  def max_note_length, do: @max_note_length

  @doc false
  def create_changeset(dismissal \\ %__MODULE__{}, attrs) do
    dismissal
    |> cast(attrs, [
      :project_id,
      :flow_id,
      :finding_key,
      :rule_id,
      :rule_version,
      :evidence_fingerprint,
      :reason_code,
      :note,
      :dismissed_by_id
    ])
    |> validate_required([
      :project_id,
      :flow_id,
      :finding_key,
      :rule_id,
      :rule_version,
      :evidence_fingerprint,
      :reason_code,
      :dismissed_by_id
    ])
    |> validate_inclusion(:reason_code, @reason_codes)
    |> validate_length(:note, max: @max_note_length)
    |> validate_note_for_other()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:dismissed_by_id)
    |> check_constraint(:reason_code, name: :flow_finding_dismissals_reason_code_check)
    |> check_constraint(:note, name: :flow_finding_dismissals_other_requires_note_check)
    |> unique_constraint([:flow_id, :finding_key, :rule_version, :evidence_fingerprint],
      name: :flow_finding_dismissals_active_idx
    )
  end

  defp validate_note_for_other(changeset) do
    reason = get_field(changeset, :reason_code)
    note = changeset |> get_field(:note) |> to_string() |> String.trim()

    if reason == "other" and note == "" do
      add_error(changeset, :note, "can't be blank for this reason")
    else
      changeset
    end
  end
end
