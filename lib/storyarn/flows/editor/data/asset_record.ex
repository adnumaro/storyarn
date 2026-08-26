defmodule Storyarn.Flows.Editor.Data.AssetRecord do
  @moduledoc """
  Consumer-local projection of an active project asset used by Flow authoring.

  Editor owns this read shape, not the shared `assets` table. Asset lifecycle
  and storage remain outside the Flow editor capability.
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

    timestamps(type: :utc_datetime)
  end
end
