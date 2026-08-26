defmodule Storyarn.Platform.GlobalSearch.Persistence.BlockRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :variable_name, :string
    field :sheet_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
