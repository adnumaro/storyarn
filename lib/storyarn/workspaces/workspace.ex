defmodule Storyarn.Workspaces.Workspace do
  @moduledoc """
  Schema for workspaces.

  A workspace is a container for projects that can be shared with team members.
  Each user has at least one workspace (created on registration).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.Workspaces.WorkspaceMembership

  # Color format: hex color with 3, 6, or 8 characters (e.g., #fff, #3b82f6, #3b82f680)
  @color_format ~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          slug: String.t() | nil,
          banner_url: String.t() | nil,
          color: String.t() | nil,
          source_locale: String.t() | nil,
          owner_id: integer() | nil,
          owner: User.t() | Ecto.Association.NotLoaded.t() | nil,
          memberships: [WorkspaceMembership.t()] | Ecto.Association.NotLoaded.t(),
          members: [User.t()] | Ecto.Association.NotLoaded.t(),
          projects: [Project.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "workspaces" do
    field :name, :string
    field :description, :string
    field :slug, :string
    field :banner_url, :string
    field :color, :string
    field :source_locale, :string, default: "en"

    belongs_to :owner, User
    has_many :memberships, WorkspaceMembership
    has_many :members, through: [:memberships, :user]
    has_many :projects, Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new workspace.
  """
  def create_changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :description, :slug, :banner_url, :color, :source_locale])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_color()
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for updating a workspace.
  """
  def update_changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :description, :banner_url, :color, :source_locale])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_color()
  end

  defp validate_color(changeset) do
    case get_change(changeset, :color) do
      nil ->
        changeset

      _color ->
        validate_format(changeset, :color, @color_format,
          message: "must be a valid hex color (e.g., #3b82f6)"
        )
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
  end
end
