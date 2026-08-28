defmodule Storyarn.Scenes.References.Projections.TableColumnRecord do
  @moduledoc "References-owned consumer-local SQL projection used to validate and maintain Scene reference indexes."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_columns" do
    field :name, :string
    field :slug, :string
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
