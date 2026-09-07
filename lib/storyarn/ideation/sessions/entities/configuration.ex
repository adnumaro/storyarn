defmodule Storyarn.Ideation.Sessions.Configuration do
  @moduledoc "Session-owned configuration preferences; performs no persistence or execution."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :rounds_enabled, :boolean, default: false
    field :timer_enabled, :boolean, default: false
    field :timer_seconds, :integer
    field :default_visibility, Ecto.Enum, values: [:private, :shared], default: :private
    field :publication_policy, Ecto.Enum, values: [:author_only, :facilitator_assisted], default: :author_only
  end

  def changeset(configuration, attrs) do
    configuration
    |> cast(attrs, [:rounds_enabled, :timer_enabled, :timer_seconds, :default_visibility, :publication_policy])
    |> validate_required([:rounds_enabled, :timer_enabled, :default_visibility, :publication_policy])
    |> validate_number(:timer_seconds, greater_than_or_equal_to: 15, less_than_or_equal_to: 86_400)
    |> require_timer_duration()
  end

  defp require_timer_duration(changeset) do
    if get_field(changeset, :timer_enabled),
      do: validate_required(changeset, [:timer_seconds]),
      else: changeset
  end
end
