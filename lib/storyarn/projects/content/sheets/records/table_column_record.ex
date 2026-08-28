defmodule Storyarn.Projects.Persistence.TableColumnRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.SheetNaming

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

  @doc "Import changeset mirroring the Sheet tool's create rules."
  def create_changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :type, :is_constant, :required, :position, :config, :block_id])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @column_types)
    |> generate_slug()
    |> unique_constraint([:block_id, :slug])
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, SheetNaming.variablify(name))
    end
  end
end
