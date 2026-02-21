defmodule Storyarn.Sheets.TableColumn do
  @moduledoc """
  Schema for table columns.

  A table column defines a typed field within a table block. Each column has a slug
  used as the 4th level in variable reference paths: `sheet.table.row.column`.

  Column types reuse the same types as regular blocks, except `rich_text` which is
  explicitly excluded — tables use plain text only.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Sheets.Block

  @column_types ~w(number text boolean select multi_select date)

  schema "table_columns" do
    field :name, :string
    field :slug, :string
    field :type, :string, default: "number"
    field :is_constant, :boolean, default: false
    field :required, :boolean, default: false
    field :position, :integer, default: 0
    field :config, :map, default: %{}

    belongs_to :block, Block

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the list of valid column types."
  def types, do: @column_types

  @doc "Changeset for creating a new table column."
  def create_changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :type, :is_constant, :required, :position, :config, :block_id])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @column_types)
    |> generate_slug()
    |> unique_constraint([:block_id, :slug])
  end

  @doc "Changeset for updating a table column."
  def update_changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :type, :is_constant, :required, :config])
    |> validate_inclusion(:type, @column_types)
    |> maybe_regenerate_slug()
  end

  @doc "Changeset for updating only the position."
  def position_changeset(column, attrs) do
    column
    |> cast(attrs, [:position])
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, Block.slugify(name))
    end
  end

  defp maybe_regenerate_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, Block.slugify(name))
    end
  end
end
