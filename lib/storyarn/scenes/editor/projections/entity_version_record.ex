defmodule Storyarn.Scenes.Editor.Projections.EntityVersionRecord do
  @moduledoc """
  Editor-owned read projection for a scene's current version association.

  Version lifecycle and writes remain owned by the Versioning capability.
  """

  use Ecto.Schema

  alias Storyarn.Scenes.Editor.Projections.ProjectRecord
  alias Storyarn.Scenes.Editor.Projections.UserRecord

  @type t :: %__MODULE__{}

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
end
