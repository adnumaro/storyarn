defmodule Storyarn.Flows.Flow do
  @moduledoc """
  Schema for flows.

  A flow is a visual graph representing narrative structure, dialogue trees,
  or game logic. Each flow belongs to a project and contains nodes and connections.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.{FlowConnection, FlowNode}
  alias Storyarn.Projects.Project

  # Shortcut format: lowercase, alphanumeric, dots and hyphens allowed, no spaces
  # Examples: chapter-1, quest.main, dialogue.intro
  @shortcut_format ~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          description: String.t() | nil,
          is_main: boolean(),
          settings: map(),
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          nodes: [FlowNode.t()] | Ecto.Association.NotLoaded.t(),
          connections: [FlowConnection.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flows" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :is_main, :boolean, default: false
    field :settings, :map, default: %{}

    belongs_to :project, Project
    has_many :nodes, FlowNode
    has_many :connections, FlowConnection

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new flow.
  """
  def create_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:name, :shortcut, :description, :is_main, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_shortcut()
  end

  @doc """
  Changeset for updating a flow.
  """
  def update_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:name, :shortcut, :description, :is_main, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_shortcut()
  end

  # Private functions

  defp validate_shortcut(changeset) do
    changeset
    |> validate_length(:shortcut, min: 1, max: 50)
    |> validate_format(:shortcut, @shortcut_format,
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., chapter-1)"
    )
    |> unique_constraint(:shortcut,
      name: :flows_project_shortcut_unique,
      message: "is already taken in this project"
    )
  end
end
