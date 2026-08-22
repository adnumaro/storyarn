defmodule Storyarn.Sheets.Persistence.AssetRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "assets" do
    field :filename, :string
    field :content_type, :string
    field :metadata, :map, default: %{}
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
