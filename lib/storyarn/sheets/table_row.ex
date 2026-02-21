defmodule Storyarn.Sheets.TableRow do
  @moduledoc """
  Schema for table rows.

  A table row represents a single record within a table block. Each row has a slug
  used as the 3rd level in variable reference paths: `sheet.table.row.column`.

  Cell values are stored as a JSONB map of `column_slug => value`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Sheets.Block

  schema "table_rows" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    field :cells, :map, default: %{}

    belongs_to :block, Block

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a new table row."
  def create_changeset(row, attrs) do
    row
    |> cast(attrs, [:name, :position, :cells, :block_id])
    |> validate_required([:name])
    |> generate_slug()
    |> unique_constraint([:block_id, :slug])
  end

  @doc "Changeset for updating a table row."
  def update_changeset(row, attrs) do
    row
    |> cast(attrs, [:name])
    |> maybe_regenerate_slug()
  end

  @doc "Changeset for updating only the position."
  def position_changeset(row, attrs) do
    row
    |> cast(attrs, [:position])
  end

  @doc "Changeset for updating cells."
  def cells_changeset(row, attrs) do
    row
    |> cast(attrs, [:cells])
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
