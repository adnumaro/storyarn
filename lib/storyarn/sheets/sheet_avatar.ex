defmodule Storyarn.Sheets.SheetAvatar do
  @moduledoc """
  Schema for avatars attached to a sheet.

  Each sheet can have multiple avatars (expressions, poses, costumes).
  One avatar per sheet is marked as `is_default` and used as the primary display image.
  Avatars are ordered by position within the sheet.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Assets.Asset
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Sheets.Sheet

  schema "sheet_avatars" do
    field :name, :string
    field :notes, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false

    belongs_to :sheet, Sheet
    belongs_to :asset, Asset

    timestamps(type: :utc_datetime)
  end

  def create_changeset(avatar, attrs) do
    avatar
    |> cast(attrs, [:name, :notes, :position, :is_default, :sheet_id, :asset_id])
    |> validate_required([:sheet_id, :asset_id])
    |> maybe_variablify_name()
    |> foreign_key_constraint(:sheet_id)
    |> foreign_key_constraint(:asset_id)
    |> unique_constraint([:sheet_id, :asset_id])
  end

  def update_changeset(avatar, attrs) do
    avatar
    |> cast(attrs, [:name, :notes, :is_default])
    |> maybe_variablify_name()
  end

  defp maybe_variablify_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      "" -> changeset
      name -> put_change(changeset, :name, NameNormalizer.variablify(name))
    end
  end
end
