defmodule Storyarn.Ideation.Sessions.Round do
  @moduledoc """
  A session-owned creative round. Rounds are horizontal bands of the session
  canvas, stacked in chronological order; `canvas_offset_y` is the canvas y of
  the round's header and note positions inside the band are relative to it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "ideation_rounds" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :number, :integer
    field :prompt, :string
    field :status, Ecto.Enum, values: [:active, :closed], default: :active
    field :canvas_offset_y, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(round, attrs) do
    round
    |> cast(attrs, [:prompt])
    |> update_change(:prompt, fn
      prompt when is_binary(prompt) -> String.trim(prompt)
      other -> other
    end)
    |> validate_length(:prompt, max: 2000, count: :codepoints)
    |> unique_constraint([:session_id, :number])
    |> check_constraint(:prompt, name: :ideation_rounds_prompt_length)
  end

  def lifecycle_changeset(round, attrs) do
    round
    |> change(attrs)
    |> unique_constraint(:status, name: :ideation_rounds_one_active_per_session)
    |> check_constraint(:status, name: :ideation_rounds_lifecycle_valid)
  end
end
