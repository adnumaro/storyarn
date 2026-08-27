defmodule Storyarn.Flows.References.Projections.AssetRecord do
  @moduledoc "Consumer-owned projection of asset facts required by Flow reference validation."

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
