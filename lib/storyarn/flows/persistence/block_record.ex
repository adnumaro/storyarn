defmodule Storyarn.Flows.Persistence.BlockRecord do
  @moduledoc false

  use Ecto.Schema

  schema "blocks" do
    field :type, :string
    field :sheet_id, :id
    field :deleted_at, :utc_datetime
  end
end
