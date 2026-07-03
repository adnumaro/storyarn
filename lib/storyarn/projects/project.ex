defmodule Storyarn.Projects.Project do
  @moduledoc """
  Schema for projects.

  A project is a narrative design workspace that can be shared with team members.
  Projects belong to a workspace.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.ProductMetrics.Taxonomy
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Workspaces.Workspace

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          description: String.t() | nil,
          project_type: String.t() | nil,
          project_subtype: String.t() | nil,
          project_type_other: String.t() | nil,
          settings: map() | nil,
          owner_id: integer() | nil,
          owner: User.t() | NotLoaded.t() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | NotLoaded.t() | nil,
          memberships: [ProjectMembership.t()] | NotLoaded.t(),
          members: [User.t()] | NotLoaded.t(),
          invitations: [ProjectInvitation.t()] | NotLoaded.t(),
          auto_snapshots_enabled: boolean(),
          auto_version_flows: boolean(),
          auto_version_scenes: boolean(),
          auto_version_sheets: boolean(),
          restoration_in_progress: boolean(),
          restoration_started_by_id: integer() | nil,
          restoration_started_at: DateTime.t() | nil,
          deleted_at: DateTime.t() | nil,
          deleted_by_id: integer() | nil,
          created_from_template_version_id: integer() | nil,
          created_from_template_version: ProjectTemplateVersion.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          last_activity_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :project_type, :string
    field :project_subtype, :string
    field :project_type_other, :string
    field :settings, :map, default: %{}
    field :auto_snapshots_enabled, :boolean, default: true
    field :auto_version_flows, :boolean, default: true
    field :auto_version_scenes, :boolean, default: true
    field :auto_version_sheets, :boolean, default: true

    field :restoration_in_progress, :boolean, default: false
    belongs_to :restoration_started_by, User
    field :restoration_started_at, :utc_datetime

    field :deleted_at, :utc_datetime
    belongs_to :deleted_by, User
    field :last_activity_at, :utc_datetime
    belongs_to :created_from_template_version, ProjectTemplateVersion

    field :snapshot_count, :integer, virtual: true, default: 0

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
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :project_type,
      :project_subtype,
      :project_type_other,
      :settings,
      :workspace_id
    ])
    |> validate_required([:name, :slug, :project_type])
    |> validate_project_fields()
    |> validate_slug()
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:workspace_id, :slug])
  end

  defp validate_slug(changeset), do: Storyarn.Shared.Validations.validate_slug(changeset)

  @doc """
  Changeset for validating the new-project form before the slug is generated.
  """
  def create_form_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :project_type, :project_subtype, :project_type_other, :settings])
    |> validate_required([:name, :project_type])
    |> validate_project_fields()
  end

  @doc """
  Changeset for updating a project.
  """
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :description,
      :project_type,
      :project_subtype,
      :project_type_other,
      :settings,
      :auto_snapshots_enabled,
      :auto_version_flows,
      :auto_version_scenes,
      :auto_version_sheets
    ])
    |> validate_required([:name])
    |> validate_project_fields()
  end

  @doc """
  Changeset for soft-deleting a project.
  """
  def soft_delete_changeset(project, attrs) do
    project
    |> cast(attrs, [:deleted_at, :deleted_by_id])
    |> validate_required([:deleted_at])
  end

  @doc """
  Changeset for restoring a soft-deleted project.
  """
  def restore_changeset(project) do
    change(project, %{deleted_at: nil, deleted_by_id: nil})
  end

  @doc """
  Extracts custom theme colors from project settings.
  Returns `%{primary: "#hex", accent: "#hex"}` or `nil` if not set.
  """
  def theme_colors(%__MODULE__{settings: %{"theme" => %{"primary" => p, "accent" => a}}})
      when is_binary(p) and is_binary(a), do: %{primary: p, accent: a}

  def theme_colors(_), do: nil

  defp validate_project_fields(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_length(:project_type_other, max: 120)
    |> validate_inclusion(:project_type, Taxonomy.project_types())
    |> validate_project_subtype()
    |> validate_project_type_other()
  end

  defp validate_project_subtype(changeset) do
    project_type = get_field(changeset, :project_type)

    cond do
      project_type in ["game", "film", "novel"] ->
        changeset
        |> validate_required([:project_subtype])
        |> validate_change(:project_subtype, &project_subtype_error(project_type, &1, &2))

      project_type == "other" ->
        changeset

      true ->
        changeset
    end
  end

  defp project_subtype_error(project_type, field, project_subtype) do
    if Taxonomy.known_project_subtype?(project_type, project_subtype) do
      []
    else
      [{field, "is invalid"}]
    end
  end

  defp validate_project_type_other(changeset) do
    if get_field(changeset, :project_type) == "other" do
      validate_required(changeset, [:project_type_other])
    else
      changeset
    end
  end
end
