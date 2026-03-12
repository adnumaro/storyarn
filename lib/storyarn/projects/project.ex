defmodule Storyarn.Projects.Project do
  @moduledoc """
  Schema for projects.

  A project is a narrative design workspace that can be shared with team members.
  Projects belong to a workspace.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.{ProjectInvitation, ProjectMembership}
  alias Storyarn.Workspaces.Workspace

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          description: String.t() | nil,
          settings: map() | nil,
          owner_id: integer() | nil,
          owner: User.t() | Ecto.Association.NotLoaded.t() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | Ecto.Association.NotLoaded.t() | nil,
          memberships: [ProjectMembership.t()] | Ecto.Association.NotLoaded.t(),
          members: [User.t()] | Ecto.Association.NotLoaded.t(),
          invitations: [ProjectInvitation.t()] | Ecto.Association.NotLoaded.t(),
          auto_snapshots_enabled: boolean(),
          auto_version_flows: boolean(),
          auto_version_scenes: boolean(),
          auto_version_sheets: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :settings, :map, default: %{}
    field :auto_snapshots_enabled, :boolean, default: true
    field :auto_version_flows, :boolean, default: true
    field :auto_version_scenes, :boolean, default: true
    field :auto_version_sheets, :boolean, default: true

    belongs_to :owner, User
    belongs_to :workspace, Workspace
    has_many :memberships, ProjectMembership
    has_many :members, through: [:memberships, :user]
    has_many :invitations, ProjectInvitation

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new project.
  """
  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :slug, :description, :settings, :workspace_id])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_slug()
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:workspace_id, :slug])
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
  end

  @doc """
  Changeset for updating a project.
  """
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :description,
      :settings,
      :auto_snapshots_enabled,
      :auto_version_flows,
      :auto_version_scenes,
      :auto_version_sheets
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
  end

  @doc """
  Extracts custom theme colors from project settings.
  Returns `%{primary: "#hex", accent: "#hex"}` or `nil` if not set.
  """
  def theme_colors(%__MODULE__{settings: %{"theme" => %{"primary" => p, "accent" => a}}})
      when is_binary(p) and is_binary(a),
      do: %{primary: p, accent: a}

  def theme_colors(_), do: nil
end
