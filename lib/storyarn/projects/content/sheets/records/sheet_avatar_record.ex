defmodule Storyarn.Projects.Persistence.SheetAvatarRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.SheetNaming

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :notes, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, Asset, where: [deleted_at: nil]

    timestamps(type: :utc_datetime)
  end

  @doc "Import changeset mirroring the Sheet tool's create rules."
  def create_changeset(avatar, attrs) do
    avatar
    |> cast(attrs, [:name, :notes, :position, :is_default, :sheet_id, :asset_id])
    |> validate_required([:sheet_id, :asset_id])
    |> maybe_variablify_name()
    |> foreign_key_constraint(:sheet_id)
    |> foreign_key_constraint(:asset_id)
    |> unique_constraint([:sheet_id, :asset_id])
  end

  defp maybe_variablify_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      "" -> changeset
      name -> put_change(changeset, :name, SheetNaming.variablify(name))
    end
  end
end
