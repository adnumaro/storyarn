defmodule Storyarn.Pages.Page do
  @moduledoc """
  Schema for pages.

  A page is a node in the project's content tree, similar to a Notion page.
  Pages can contain blocks (dynamic content fields) and can have child pages.

  Any page can have children AND content (blocks). The UI adapts based on what
  the page contains. This matches the Flows model for consistency.

  Fields:
  - `description` - Rich text for annotations (constant, not referenceable)
  - `parent_id` - FK to parent page (nil for root level)
  - `position` - Order among siblings
  - `deleted_at` - Soft delete support
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Assets.Asset
  alias Storyarn.Pages.{Block, PageVersion}
  alias Storyarn.Projects.Project

  # Shortcut format: lowercase, alphanumeric, dots and hyphens allowed, no spaces
  # Examples: mc.jaime, loc.tavern, items.sword, quest-1
  @shortcut_format ~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/

  # Color format: hex color with 3, 6, or 8 characters (e.g., #fff, #3b82f6, #3b82f680)
  @color_format ~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          description: String.t() | nil,
          color: String.t() | nil,
          position: integer() | nil,
          avatar_asset_id: integer() | nil,
          avatar_asset: Asset.t() | Ecto.Association.NotLoaded.t() | nil,
          banner_asset_id: integer() | nil,
          banner_asset: Asset.t() | Ecto.Association.NotLoaded.t() | nil,
          current_version_id: integer() | nil,
          current_version: PageVersion.t() | Ecto.Association.NotLoaded.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: integer() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          children: [t()] | Ecto.Association.NotLoaded.t(),
          blocks: [Block.t()] | Ecto.Association.NotLoaded.t(),
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pages" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :color, :string
    field :position, :integer, default: 0
    field :deleted_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :parent, __MODULE__
    belongs_to :avatar_asset, Asset
    belongs_to :banner_asset, Asset
    belongs_to :current_version, PageVersion
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :blocks, Block
    has_many :versions, PageVersion

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new page.
  """
  def create_changeset(page, attrs) do
    page
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :color,
      :avatar_asset_id,
      :banner_asset_id,
      :parent_id,
      :position
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_shortcut()
    |> validate_color()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:avatar_asset_id)
    |> foreign_key_constraint(:banner_asset_id)
  end

  @doc """
  Changeset for updating a page.
  """
  def update_changeset(page, attrs) do
    page
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :color,
      :avatar_asset_id,
      :banner_asset_id,
      :parent_id,
      :position
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_shortcut()
    |> validate_color()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:avatar_asset_id)
    |> foreign_key_constraint(:banner_asset_id)
  end

  @doc """
  Changeset for moving a page (changing parent or position).
  """
  def move_changeset(page, attrs) do
    page
    |> cast(attrs, [:parent_id, :position])
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for soft deleting a page.
  """
  def delete_changeset(page) do
    page
    |> change(%{deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  @doc """
  Changeset for restoring a soft-deleted page.
  """
  def restore_changeset(page) do
    page
    |> change(%{deleted_at: nil})
  end

  @doc """
  Changeset for updating the current version pointer.
  """
  def version_changeset(page, attrs) do
    page
    |> cast(attrs, [:current_version_id])
    |> foreign_key_constraint(:current_version_id)
  end

  @doc """
  Returns true if the page is soft-deleted.
  """
  def deleted?(%__MODULE__{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  # Private functions

  defp validate_shortcut(changeset) do
    changeset
    |> validate_length(:shortcut, min: 1, max: 50)
    |> validate_format(:shortcut, @shortcut_format,
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., mc.jaime)"
    )
    |> unique_constraint(:shortcut,
      name: :pages_project_shortcut_unique,
      message: "is already taken in this project"
    )
  end

  defp validate_color(changeset) do
    case get_change(changeset, :color) do
      nil ->
        changeset

      _color ->
        validate_format(changeset, :color, @color_format,
          message: "must be a valid hex color (e.g., #3b82f6)"
        )
    end
  end
end
