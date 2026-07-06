defmodule Storyarn.ProjectTemplates.ProjectTemplateVersion do
  @moduledoc """
  Immutable content artifact for a project template publication.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_template_id: integer() | nil,
          project_template: ProjectTemplate.t() | NotLoaded.t() | nil,
          version_number: pos_integer() | nil,
          source_project_id: integer() | nil,
          source_project: Project.t() | NotLoaded.t() | nil,
          snapshot_storage_key: String.t() | nil,
          asset_manifest_storage_key: String.t() | nil,
          checksum: String.t() | nil,
          version_notes: String.t() | nil,
          entity_counts: map(),
          preview: map(),
          audit_report: map(),
          published_by_id: integer() | nil,
          published_by: User.t() | NotLoaded.t() | nil,
          published_at: DateTime.t() | nil,
          installs: [ProjectTemplateInstall.t()] | NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_template_versions" do
    field :version_number, :integer
    field :snapshot_storage_key, :string
    field :asset_manifest_storage_key, :string
    field :checksum, :string
    field :version_notes, :string
    field :entity_counts, :map, default: %{}
    field :preview, :map, default: %{}
    field :audit_report, :map, default: %{}
    field :published_at, :utc_datetime

    belongs_to :project_template, ProjectTemplate
    belongs_to :source_project, Project
    belongs_to :published_by, User
    has_many :installs, ProjectTemplateInstall

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creation-only changeset. Template versions are immutable after insertion.
  """
  def create_changeset(version, attrs) do
    version
    |> cast(attrs, [
      :version_number,
      :snapshot_storage_key,
      :asset_manifest_storage_key,
      :checksum,
      :version_notes,
      :entity_counts,
      :preview,
      :audit_report,
      :published_at
    ])
    |> validate_required([
      :version_number,
      :snapshot_storage_key,
      :asset_manifest_storage_key,
      :checksum,
      :entity_counts,
      :preview,
      :audit_report,
      :published_at
    ])
    |> validate_number(:version_number, greater_than: 0)
    |> validate_length(:snapshot_storage_key, min: 1, max: 255)
    |> validate_length(:asset_manifest_storage_key, min: 1, max: 255)
    |> validate_length(:version_notes, max: 2_000)
    |> validate_format(:checksum, ~r/^[a-f0-9]{64}$/)
    |> foreign_key_constraint(:project_template_id)
    |> foreign_key_constraint(:source_project_id)
    |> foreign_key_constraint(:published_by_id)
    |> unique_constraint([:project_template_id, :version_number],
      name: :project_template_versions_template_version_unique
    )
    |> check_constraint(:version_number, name: :project_template_versions_version_number_check)
  end
end
