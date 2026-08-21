defmodule Storyarn.Flows.Persistence.AssetRecord do
  @moduledoc false

  use Ecto.Schema

  schema "assets" do
    field :filename, :string
    field :metadata, :map, default: %{}
    field :deleted_at, :utc_datetime
  end
end
