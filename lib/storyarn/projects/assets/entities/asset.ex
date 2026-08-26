defmodule Storyarn.Projects.Assets.Asset do
  @moduledoc """
  Schema for uploaded assets.

  An asset represents an uploaded file (image, audio, etc.) that belongs to a project.
  Assets are stored in Cloudflare R2 (production) or locally (development).

  ## Fields

    * `filename` - Original filename as uploaded
    * `content_type` - MIME type (e.g., "image/png", "audio/mp3")
    * `size` - File size in bytes
    * `key` - Storage key/path in the bucket
    * `url` - Persisted storage URL (not a browser authorization boundary)
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

  alias Ecto.Association.NotLoaded
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Project

  @allowed_content_types ~w(
    image/jpeg image/png image/gif image/webp
    audio/mpeg audio/wav audio/ogg audio/webm
    application/pdf
  )
  @sanitized_svg_content_types ~w(image/svg+xml)
  @snapshot_restore_content_types @allowed_content_types ++
                                    @sanitized_svg_content_types ++ ["application/octet-stream"]
  @max_asset_size 52_428_800
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @max_asset_id 9_223_372_036_854_775_807

  @type t :: %__MODULE__{
          id: integer() | nil,
          filename: String.t() | nil,
          content_type: String.t() | nil,
          size: integer() | nil,
          key: String.t() | nil,
          url: String.t() | nil,
          metadata: map() | nil,
          blob_hash: String.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | NotLoaded.t() | nil,
          uploaded_by_id: integer() | nil,
          uploaded_by: User.t() | NotLoaded.t() | nil,
          deleted_at: DateTime.t() | nil,
          deleted_by_id: integer() | nil,
          deleted_by: User.t() | NotLoaded.t() | nil,
          deletion_reason: String.t() | nil,
          deletion_generation: non_neg_integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "assets" do
    field :filename, :string
    field :content_type, :string
    field :size, :integer
    field :key, :string
    field :url, :string
    field :metadata, :map, default: %{}
    field :blob_hash, :string
    field :deleted_at, :utc_datetime
    field :deletion_reason, :string
    field :deletion_generation, :integer, default: 0

    belongs_to :project, Project
    belongs_to :uploaded_by, User
    belongs_to :deleted_by, User

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
  Returns the optimized web URL if a variant exists, otherwise the original URL.
  """
  def display_url(%__MODULE__{metadata: %{"web_url" => url}}) when is_binary(url), do: url
  def display_url(%__MODULE__{url: url}), do: url
  def display_url(%{url: url}) when is_binary(url), do: url
  def display_url(nil), do: nil

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
    create_changeset(asset, attrs, @allowed_content_types)
  end

  @doc """
  Changeset for SVGs that were sanitized by the server before storage.
  """
  def create_sanitized_svg_changeset(asset, attrs) do
    create_changeset(asset, attrs, @sanitized_svg_content_types)
  end

  @doc false
  def snapshot_restore_changeset(asset, attrs) do
    asset
    |> cast(attrs, [:filename, :content_type, :size, :key, :url, :metadata, :blob_hash])
    |> require_non_nil([:filename, :content_type, :size, :key, :blob_hash])
    |> validate_inclusion(:content_type, @snapshot_restore_content_types,
      message: "is not a supported snapshot file type"
    )
    |> validate_number(:size, greater_than_or_equal_to: 0, less_than_or_equal_to: @max_asset_size)
    |> validate_format(:blob_hash, @sha256_regex)
    |> unique_constraint(:key, name: :assets_project_id_key_index)
  end

  defp create_changeset(asset, attrs, allowed_content_types) do
    asset
    |> cast(attrs, [:filename, :content_type, :size, :key, :url, :metadata, :blob_hash])
    |> validate_required([:filename, :content_type, :size, :key])
    |> validate_inclusion(:content_type, allowed_content_types, message: "is not a supported file type")
    |> validate_number(:size, greater_than: 0, less_than_or_equal_to: @max_asset_size)
    |> unique_constraint(:key, name: :assets_project_id_key_index)
  end

  defp require_non_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if is_nil(get_field(changeset, field)),
        do: add_error(changeset, field, "can't be nil"),
        else: changeset
    end)
  end

  @doc """
  Changeset for updating asset metadata.
  """
  def update_changeset(asset, attrs) do
    cast(asset, attrs, [:url, :metadata])
  end

  @doc false
  def trash_changeset(%__MODULE__{deleted_at: nil} = asset, actor_id, reason, %DateTime{} = deleted_at)
      when reason in ["user", "snapshot_restore", "system"] do
    asset
    |> change(%{
      deleted_at: deleted_at,
      deleted_by_id: actor_id,
      deletion_reason: reason,
      deletion_generation: asset.deletion_generation + 1
    })
    |> validate_trash_actor(reason)
    |> foreign_key_constraint(:deleted_by_id)
    |> check_constraint(:deletion_generation, name: :assets_deletion_generation_non_negative)
    |> check_constraint(:deleted_at, name: :assets_trash_state_shape)
  end

  def trash_changeset(%__MODULE__{} = asset, _actor_id, _reason, _deleted_at) do
    add_error(change(asset), :deleted_at, "is already in trash")
  end

  @doc false
  def restore_changeset(%__MODULE__{deleted_at: %DateTime{}} = asset) do
    asset
    |> change(%{
      deleted_at: nil,
      deleted_by_id: nil,
      deletion_reason: nil,
      deletion_generation: asset.deletion_generation + 1
    })
    |> check_constraint(:deletion_generation, name: :assets_deletion_generation_non_negative)
    |> check_constraint(:deleted_at, name: :assets_trash_state_shape)
  end

  def restore_changeset(%__MODULE__{} = asset) do
    add_error(change(asset), :deleted_at, "is not in trash")
  end

  defp validate_trash_actor(changeset, "user") do
    validate_required(changeset, [:deleted_by_id])
  end

  defp validate_trash_actor(changeset, _reason), do: changeset

  @doc false
  @spec family_reference_ids(map() | nil) :: {:ok, [pos_integer()]} | :error
  def family_reference_ids(nil), do: {:ok, []}

  def family_reference_ids(metadata) when is_map(metadata) do
    with {:ok, web_id} <- validate_optional_asset_id(metadata, "web_asset_id"),
         {:ok, original_id} <- validate_optional_asset_id(metadata, "original_asset_id"),
         {:ok, variant_ids} <- validate_variant_asset_ids(metadata) do
      {:ok, Enum.reject([web_id, original_id | variant_ids], &is_nil/1)}
    end
  end

  def family_reference_ids(_metadata), do: :error

  defp validate_optional_asset_id(metadata, key) do
    case Map.fetch(metadata, key) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, value} -> validate_asset_id(value)
    end
  end

  defp validate_variant_asset_ids(metadata) do
    case Map.fetch(metadata, "variant_asset_ids") do
      :error -> {:ok, []}
      {:ok, nil} -> {:ok, []}
      {:ok, variants} when is_map(variants) -> validate_asset_ids(Map.values(variants))
      {:ok, _invalid} -> :error
    end
  end

  defp validate_asset_ids(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, ids} ->
      case validate_asset_id(value) do
        {:ok, id} -> {:cont, {:ok, [id | ids]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp validate_asset_id(id) when is_integer(id) and id > 0 and id <= @max_asset_id, do: {:ok, id}

  defp validate_asset_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} when integer > 0 and integer <= @max_asset_id -> {:ok, integer}
      _invalid -> :error
    end
  end

  defp validate_asset_id(_id), do: :error
end
