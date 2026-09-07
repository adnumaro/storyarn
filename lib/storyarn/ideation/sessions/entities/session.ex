defmodule Storyarn.Ideation.Sessions.Session do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Configuration

  schema "ideation_sessions" do
    field :project_id, :id
    field :created_by_id, :id
    field :facilitator_id, :id
    field :decision_owner_id, :id
    field :title, :string
    field :objective, :string
    field :context, :string
    field :status, Ecto.Enum, values: [:open, :archived], default: :open
    field :archived_at, :utc_datetime
    field :revision, :integer, default: 1
    field :configuration_version, :integer, default: 1
    embeds_one :configuration, Configuration, on_replace: :update, defaults_to_struct: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:title, :objective, :context])
    |> update_change(:title, fn
      title when is_binary(title) -> String.trim(title)
      other -> other
    end)
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
    |> validate_length(:objective, max: 4000)
    |> validate_length(:context, max: 12_000)
    |> cast_embed(:configuration, required: true, with: &Configuration.changeset/2)
  end
end
