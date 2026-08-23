defmodule Storyarn.Projects.Persistence.TableColumnRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_columns" do
    field :name, :string
    field :slug, :string
    field :type, :string
    field :is_constant, :boolean, default: false
    field :required, :boolean, default: false
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end

  @column_types ~w(number text boolean select multi_select date reference formula)

  @doc "The closed catalog of table column types a snapshot may carry."
  def types, do: @column_types
end
