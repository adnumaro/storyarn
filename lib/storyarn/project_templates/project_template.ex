defmodule Storyarn.ProjectTemplates.ProjectTemplate do
  @moduledoc """
  Mutable metadata for a published project template.

  Template content lives in immutable `ProjectTemplateVersion` artifacts. This
  schema can change name, description, status, and the current version pointer.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion

  @visibilities ~w(private public)
  @statuses ~w(active archived)

  @type t :: %__MODULE__{
          id: integer() | nil,
          owner_id: integer() | nil,
          owner: User.t() | NotLoaded.t() | nil,
          source_project_id: integer() | nil,
          source_project: Project.t() | NotLoaded.t() | nil,
          current_version_id: integer() | nil,
          current_version: ProjectTemplateVersion.t() | NotLoaded.t() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          description: String.t() | nil,
          visibility: String.t(),
          status: String.t(),
          versions: [ProjectTemplateVersion.t()] | NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_templates" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :visibility, :string, default: "private"
    field :status, :string, default: "active"

    belongs_to :owner, User
    belongs_to :source_project, Project
    belongs_to :current_version, ProjectTemplateVersion
    has_many :versions, ProjectTemplateVersion

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities
  def statuses, do: @statuses

  @doc """
  Changeset for creating a template metadata row.
  """
  def create_changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :slug, :description, :visibility, :status])
    |> validate_required([:name, :slug, :visibility, :status])
    |> validate_common()
  end

  @doc """
  Changeset for mutable metadata updates.
  """
  def update_changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :status])
    |> validate_required([:name, :status])
    |> validate_common()
  end

  def current_version_changeset(template, version_id) do
    template
    |> change(current_version_id: version_id)
    |> foreign_key_constraint(:current_version_id)
  end

  defp validate_common(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1_000)
    |> Storyarn.Shared.Validations.validate_slug()
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:source_project_id)
    |> unique_constraint([:owner_id, :slug], name: :project_templates_owner_slug_unique)
    |> unique_constraint(:slug, name: :project_templates_public_slug_unique)
    |> check_constraint(:visibility, name: :project_templates_visibility_check)
    |> check_constraint(:status, name: :project_templates_status_check)
  end
end
