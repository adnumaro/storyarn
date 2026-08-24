defmodule Storyarn.Projects.Persistence.SheetRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Assets.Asset
  alias Storyarn.Projects.Persistence.BlockRecord
  alias Storyarn.Projects.Persistence.SheetAvatarRecord

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :color, :string
    field :position, :integer, default: 0
    field :hidden_inherited_block_ids, {:array, :integer}, default: []
    field :project_id, :id
    field :parent_id, :id
    field :deleted_at, :utc_datetime

    belongs_to :banner_asset, Asset, where: [deleted_at: nil]
    has_many :avatars, SheetAvatarRecord, foreign_key: :sheet_id
    has_many :blocks, BlockRecord, foreign_key: :sheet_id

    timestamps(type: :utc_datetime)
  end

  @shortcut_format ~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/
  @color_format ~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/

  @doc "Changeset for soft deleting a sheet."
  def delete_changeset(sheet), do: change(sheet, %{deleted_at: Storyarn.Shared.TimeHelpers.now()})

  @doc "Changeset for restoring a soft-deleted sheet."
  def restore_changeset(sheet), do: change(sheet, %{deleted_at: nil})

  @doc """
  Validation-only changeset mirroring the Sheet tool's create rules.

  Project snapshot validation must reject exactly the payloads the tool
  rejects; keep both rule sets in lockstep.
  """
  def create_changeset(sheet, attrs) do
    sheet
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :color,
      :banner_asset_id,
      :parent_id,
      :position,
      :hidden_inherited_block_ids
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:shortcut, min: 1, max: 50)
    |> validate_format(:shortcut, @shortcut_format,
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., mc.jaime)"
    )
    |> validate_color()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:banner_asset_id)
  end

  defp validate_color(changeset) do
    case get_change(changeset, :color) do
      nil ->
        changeset

      _color ->
        validate_format(changeset, :color, @color_format, message: "must be a valid hex color (e.g., #3b82f6)")
    end
  end
end
