defmodule Storyarn.Projects.Persistence.TableRowRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.SheetNaming

  @type t :: %__MODULE__{}

  schema "table_rows" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    field :cells, :map, default: %{}
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc "Import changeset mirroring the Sheet tool's create rules."
  def create_changeset(row, attrs) do
    row
    |> cast(attrs, [:name, :position, :cells, :block_id])
    |> validate_required([:name])
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
