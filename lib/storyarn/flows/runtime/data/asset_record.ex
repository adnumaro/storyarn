defmodule Storyarn.Flows.Runtime.Data.AssetRecord do
  @moduledoc "Runtime-owned media projection used to render speaker avatars."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "assets" do
    field :filename, :string
    field :metadata, :map, default: %{}
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
