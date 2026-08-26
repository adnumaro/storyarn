defmodule Storyarn.Sheets.Versioning.EntityVersionRecord do
  @moduledoc """
  Sheet-owned persistence record for the shared `entity_versions` table.

  Keeping this record inside the Sheet bounded context lets Sheet versioning
  evolve without importing Project's generic versioning model. The database
  table is intentionally shared during the first separation phase.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Sheets.Versioning.Data.ProjectRecord
  alias Storyarn.Sheets.Versioning.Data.UserRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          entity_type: String.t(),
          entity_id: integer(),
          project_id: integer(),
          version_number: integer(),
          title: String.t() | nil,
          description: String.t() | nil,
          change_summary: String.t() | nil,
          change_details: map() | nil,
          storage_key: String.t(),
          snapshot_size_bytes: non_neg_integer(),
          checksum: String.t(),
          is_auto: boolean(),
          created_by_id: integer() | nil,
          created_by: UserRecord.t() | NotLoaded.t() | nil,
          project: ProjectRecord.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "entity_versions" do
    field :entity_type, :string
    field :entity_id, :integer
    field :version_number, :integer
    field :title, :string
    field :description, :string
    field :change_summary, :string
    field :change_details, :map
    field :storage_key, :string
    field :snapshot_size_bytes, :integer
    field :checksum, :string
    field :is_auto, :boolean, default: false

    belongs_to :project, ProjectRecord
    belongs_to :created_by, UserRecord

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc false
  def create_changeset(version, attrs) do
    version
    |> cast(attrs, [
      :entity_type,
      :entity_id,
      :project_id,
      :version_number,
      :title,
      :description,
      :change_summary,
      :change_details,
      :storage_key,
      :snapshot_size_bytes,
      :checksum,
      :is_auto,
      :created_by_id
    ])
    |> validate_required([
      :entity_type,
      :entity_id,
      :project_id,
      :version_number,
      :storage_key,
      :snapshot_size_bytes,
      :checksum
    ])
    |> validate_inclusion(:entity_type, ["sheet"])
    |> validate_length(:title, max: 255)
    |> validate_number(:snapshot_size_bytes, greater_than_or_equal_to: 0)
    |> validate_format(:checksum, ~r/\A[0-9a-f]{64}\z/)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:checksum, name: :entity_versions_checksum_format)
    |> unique_constraint([:entity_type, :entity_id, :version_number],
      name: :entity_versions_type_id_number_unique
    )
  end

  @doc false
  def update_changeset(version, attrs) do
    version
    |> cast(attrs, [:title, :description])
    |> put_change(:is_auto, false)
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 500)
  end
end
