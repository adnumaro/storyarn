defmodule Storyarn.Scenes.ExplorationSession do
  @moduledoc """
  Schema for persisting exploration mode progress.

  One session per user per project. Stores variable overrides,
  collected item IDs, character positions, and camera state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "exploration_sessions" do
    belongs_to :user, Storyarn.Accounts.User
    belongs_to :project, Storyarn.Projects.Project
    belongs_to :scene, Storyarn.Scenes.Scene

    field :variable_values, :map, default: %{}
    field :collected_ids, {:array, :string}, default: []
    field :player_positions, :map
    field :camera_state, :map

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(user_id project_id)a
  @optional_fields ~w(scene_id variable_values collected_ids player_positions camera_state)a

  def changeset(session, attrs) do
    session
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:scene_id)
    |> unique_constraint([:user_id, :project_id])
  end
end
