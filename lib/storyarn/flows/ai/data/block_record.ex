defmodule Storyarn.Flows.AI.Data.BlockRecord do
  @moduledoc "AI-owned read projection of Sheet blocks included as Flow context evidence."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :sheet_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
