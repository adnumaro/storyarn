defmodule Storyarn.Platform.GlobalSearch.Persistence.TableColumnRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_columns" do
    field :name, :string
    field :slug, :string
    field :config, :map, default: %{}
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
