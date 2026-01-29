defmodule Storyarn.Assets.Asset do
  @moduledoc """
  Schema for uploaded assets.

  An asset represents an uploaded file (image, audio, etc.) that belongs to a project.
  Assets are stored in Cloudflare R2 (production) or locally (development).

  ## Fields

    * `filename` - Original filename as uploaded
    * `content_type` - MIME type (e.g., "image/png", "audio/mp3")
    * `size` - File size in bytes
    * `key` - Storage key/path in the bucket
    * `url` - Public URL for accessing the asset
    * `metadata` - Additional metadata (e.g., width, height for images, thumbnail_key)

  ## Metadata Examples

      # For images
      %{
        "width" => 1920,
        "height" => 1080,
        "thumbnail_key" => "projects/abc123/thumbnails/image_thumb.jpg"
      }

      # For audio
      %{
        "duration" => 120.5
      }
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project

  @allowed_content_types ~w(
    image/jpeg image/png image/gif image/webp image/svg+xml
    audio/mpeg audio/wav audio/ogg audio/webm
    application/pdf
  )

  schema "assets" do
    field :filename, :string
    field :content_type, :string
    field :size, :integer
    field :key, :string
    field :url, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Project
    belongs_to :uploaded_by, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of allowed content types.
  """
  def allowed_content_types, do: @allowed_content_types

  @doc """
  Checks if a content type is allowed.
  """
  def allowed_content_type?(content_type) do
    content_type in @allowed_content_types
  end

  @doc """
  Checks if an asset is an image.
  """
  def image?(%__MODULE__{content_type: content_type}) do
    String.starts_with?(content_type, "image/")
  end

  @doc """
  Checks if an asset is audio.
  """
  def audio?(%__MODULE__{content_type: content_type}) do
    String.starts_with?(content_type, "audio/")
  end

  @doc """
  Changeset for creating an asset.
  """
  def create_changeset(asset, attrs) do
    asset
    |> cast(attrs, [:filename, :content_type, :size, :key, :url, :metadata])
    |> validate_required([:filename, :content_type, :size, :key])
    |> validate_inclusion(:content_type, @allowed_content_types,
      message: "is not a supported file type"
    )
    |> validate_number(:size, greater_than: 0)
    |> unique_constraint(:key, name: :assets_project_id_key_index)
  end

  @doc """
  Changeset for updating asset metadata.
  """
  def update_changeset(asset, attrs) do
    asset
    |> cast(attrs, [:url, :metadata])
  end
end
