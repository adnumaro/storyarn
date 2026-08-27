defmodule Storyarn.Sheets.Editor.Projections.AssetRecord do
  @moduledoc """
  Sheet-editor projection of an asset attached to authored Sheet content.

  The editor owns this read shape even while it shares the `assets` table with
  Projects. Asset lifecycle and storage writes remain outside this projection.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "assets" do
    field :filename, :string
    field :content_type, :string
    field :size, :integer
    field :key, :string
    field :url, :string
    field :metadata, :map, default: %{}
    field :blob_hash, :string
    field :project_id, :id
    field :uploaded_by_id, :id
    field :deleted_at, :utc_datetime
    field :deleted_by_id, :id
    field :deletion_reason, :string
    field :deletion_generation, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
