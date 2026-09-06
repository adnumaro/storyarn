defmodule Storyarn.Flows.Runtime.Projections.AssetRecord do
  @moduledoc "Runtime-owned media projection used to render speaker avatars and dialogue voice."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "assets" do
    field :filename, :string
    field :project_id, :id
    field :content_type, :string
    field :metadata, :map, default: %{}
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
