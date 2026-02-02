defmodule Storyarn.Pages.Page do
  @moduledoc """
  Schema for pages.

  A page is a node in the project's content tree, similar to a Notion page.
  Pages can contain blocks (dynamic content fields) and can have child pages.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Assets.Asset
  alias Storyarn.Pages.Block
  alias Storyarn.Projects.Project

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          position: integer() | nil,
          avatar_asset_id: integer() | nil,
          avatar_asset: Asset.t() | Ecto.Association.NotLoaded.t() | nil,
          banner_asset_id: integer() | nil,
          banner_asset: Asset.t() | Ecto.Association.NotLoaded.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: integer() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          children: [t()] | Ecto.Association.NotLoaded.t(),
          blocks: [Block.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pages" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :project, Project
    belongs_to :parent, __MODULE__
    belongs_to :avatar_asset, Asset
    belongs_to :banner_asset, Asset
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :blocks, Block

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new page.
  """
  def create_changeset(page, attrs) do
    page
    |> cast(attrs, [:name, :avatar_asset_id, :banner_asset_id, :parent_id, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:avatar_asset_id)
    |> foreign_key_constraint(:banner_asset_id)
  end

  @doc """
  Changeset for updating a page.
  """
  def update_changeset(page, attrs) do
    page
    |> cast(attrs, [:name, :avatar_asset_id, :banner_asset_id, :parent_id, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
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
end
