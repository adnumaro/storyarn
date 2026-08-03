defmodule Storyarn.Versioning.ProjectSnapshot do
  @moduledoc """
  Schema for project-level snapshots.

  Project snapshot records currently support entity JSON snapshots and the
  canonical versioned object-set metadata introduced for full project capture.
  A canonical object set is ready only through its independently checksummed
  manifest; its project JSON and asset blobs live in the same owned namespace.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer(),
          version_number: integer(),
          title: String.t() | nil,
          description: String.t() | nil,
          storage_key: String.t(),
          snapshot_size_bytes: integer(),
          checksum: String.t() | nil,
          format_version: integer() | nil,
          object_prefix: String.t() | nil,
          manifest_storage_key: String.t() | nil,
          manifest_size_bytes: integer() | nil,
          manifest_checksum: String.t() | nil,
          total_size_bytes: integer() | nil,
          object_count: integer() | nil,
          asset_count: integer() | nil,
          blob_count: integer() | nil,
          entity_counts: map(),
          created_by_id: integer() | nil,
          created_by: User.t() | NotLoaded.t() | nil,
          is_auto: boolean(),
          project: Project.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "project_snapshots" do
    field :version_number, :integer
    field :title, :string
    field :description, :string
    field :storage_key, :string
    field :snapshot_size_bytes, :integer
    field :checksum, :string
    field :format_version, :integer
    field :object_prefix, :string
    field :manifest_storage_key, :string
    field :manifest_size_bytes, :integer
    field :manifest_checksum, :string
    field :total_size_bytes, :integer
    field :object_count, :integer
    field :asset_count, :integer
    field :blob_count, :integer
    field :entity_counts, :map, default: %{}
    field :is_auto, :boolean, default: false

    belongs_to :project, Project
    belongs_to :created_by, User

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for persisting a canonical snapshot object set.

  The existing storage fields identify `project.json` so the database keeps an
  independently verified project-object digest alongside the manifest digest.
  Object-set readers still require the ready manifest key and never infer
  readiness from the project object alone.
  """
  def object_set_changeset(snapshot, attrs) do
    attrs = normalize_object_set_attrs(attrs)

    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :storage_key,
      :snapshot_size_bytes,
      :checksum,
      :entity_counts,
      :created_by_id,
      :is_auto,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count
    ])
    |> validate_required([
      :project_id,
      :version_number,
      :storage_key,
      :snapshot_size_bytes,
      :checksum,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count
    ])
    |> validate_inclusion(:format_version, [1])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:manifest_storage_key, max: 520)
    |> validate_number(:snapshot_size_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:manifest_size_bytes, greater_than: 0)
    |> validate_number(:total_size_bytes, greater_than: 0)
    |> validate_number(:object_count, greater_than_or_equal_to: 2)
    |> validate_number(:asset_count, greater_than_or_equal_to: 0)
    |> validate_number(:blob_count, greater_than_or_equal_to: 0)
    |> validate_format(:checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:manifest_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_object_counts()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:format_version, name: :project_snapshots_object_format_version)
    |> check_constraint(:object_count, name: :project_snapshots_object_counts)
    |> check_constraint(:checksum, name: :project_snapshots_checksum_format)
    |> check_constraint(:manifest_checksum, name: :project_snapshots_manifest_checksum_format)
    |> unique_constraint(:object_prefix)
    |> unique_constraint(:manifest_storage_key)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Changeset for creating a new project snapshot.
  """
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :storage_key,
      :snapshot_size_bytes,
      :checksum,
      :entity_counts,
      :created_by_id,
      :is_auto
    ])
    |> validate_required([
      :project_id,
      :version_number,
      :storage_key,
      :snapshot_size_bytes,
      :checksum
    ])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_number(:snapshot_size_bytes, greater_than_or_equal_to: 0)
    |> validate_format(:checksum, ~r/\A[0-9a-f]{64}\z/)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:checksum, name: :project_snapshots_checksum_format)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Changeset for updating title and description on an existing snapshot.
  """
  def update_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:title, :description])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
  end

  defp normalize_object_set_attrs(attrs) when is_map(attrs) do
    attrs
    |> put_alias(:storage_key, :project_storage_key)
    |> put_alias(:snapshot_size_bytes, :project_size_bytes)
    |> put_alias(:checksum, :project_checksum)
  end

  defp put_alias(attrs, destination, source) do
    destination_value = Map.get(attrs, destination) || Map.get(attrs, to_string(destination))
    source_value = Map.get(attrs, source) || Map.get(attrs, to_string(source))

    if is_nil(destination_value) and not is_nil(source_value),
      do: Map.put(attrs, destination, source_value),
      else: attrs
  end

  defp validate_object_counts(changeset) do
    object_count = get_field(changeset, :object_count)
    asset_count = get_field(changeset, :asset_count)
    blob_count = get_field(changeset, :blob_count)

    cond do
      not Enum.all?([object_count, asset_count, blob_count], &is_integer/1) ->
        changeset

      object_count != blob_count + 2 ->
        add_error(changeset, :object_count, "must equal blob count plus manifest and project objects")

      blob_count > asset_count ->
        add_error(changeset, :blob_count, "cannot exceed asset count")

      true ->
        changeset
    end
  end
end
