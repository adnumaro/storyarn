defmodule Storyarn.Ideation.Sessions.Round do
  @moduledoc """
  A session-owned creative round. Rounds are horizontal bands of the session
  canvas, stacked in chronological order. A band is as tall as its content, so
  nothing about its height is stored; note positions are relative to its header.
  Its decision lane sits under the band's content until someone moves it; a
  moved lane keeps its `x` and `y`, relative to the header, and a `version`.
  A round in progress can be private: its contributions stay with their authors
  until the facilitator reveals the round, or the timer does when asked to.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "ideation_rounds" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :number, :integer
    field :prompt, :string
    field :status, Ecto.Enum, values: [:active, :closed], default: :active
    field :private, :boolean, default: false
    field :reveal_on_expiry, :boolean, default: false
    field :revealed_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    field :decision_lane, :map, default: %{}
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

  def privacy_changeset(round, attrs) do
    round
    |> cast(attrs, [:private, :reveal_on_expiry])
    |> validate_required([:private, :reveal_on_expiry])
  end

  def lifecycle_changeset(round, attrs) do
    round
    |> change(attrs)
    |> unique_constraint(:status, name: :ideation_rounds_one_active_per_session)
    |> check_constraint(:status, name: :ideation_rounds_lifecycle_valid)
  end
end
