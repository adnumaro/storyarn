defmodule Storyarn.Assets do
  @moduledoc """
  The Assets context.

  Handles file uploads and asset management for projects.
  Supports both local storage (development) and Cloudflare R2 (production).
  """

  import Ecto.Query, warn: false
  alias Storyarn.Repo

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Projects.Project

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type asset :: Asset.t()
  @type project :: Project.t()
  @type user :: User.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type list_opts :: [
          content_type: String.t(),
          images_only: boolean(),
          search: String.t(),
          limit: non_neg_integer(),
          offset: non_neg_integer()
        ]

  @doc """
  Lists all assets for a project.

  ## Options

    * `:content_type` - Filter by content type prefix (e.g., "image/", "audio/")
    * `:images_only` - Filter to only image assets
    * `:search` - Search by filename
    * `:limit` - Maximum number of assets to return
    * `:offset` - Number of assets to skip

  """
  @spec list_assets(integer(), list_opts()) :: [asset()]
  def list_assets(project_id, opts \\ []) do
    from(a in Asset, where: a.project_id == ^project_id)
    |> apply_content_type_filter(opts)
    |> apply_images_only_filter(opts)
    |> apply_search_filter(opts)
    |> apply_pagination(opts)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  defp apply_content_type_filter(query, opts) do
    case Keyword.get(opts, :content_type) do
      nil -> query
      prefix -> where(query, [a], ilike(a.content_type, ^"#{prefix}%"))
    end
  end

  defp apply_images_only_filter(query, opts) do
    if Keyword.get(opts, :images_only) do
      where(query, [a], ilike(a.content_type, ^"image/%"))
    else
      query
    end
  end

  defp apply_search_filter(query, opts) do
    case Keyword.get(opts, :search) do
      nil ->
        query

      "" ->
        query

      term ->
        escaped = Storyarn.Shared.SearchHelpers.sanitize_like_query(term)
        where(query, [a], ilike(a.filename, ^"%#{escaped}%"))
    end
  end

  defp apply_pagination(query, opts) do
    query
    |> maybe_limit(Keyword.get(opts, :limit))
    |> maybe_offset(Keyword.get(opts, :offset))
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  @doc """
  Gets a single asset by ID within a project.

  Returns `nil` if the asset doesn't exist or doesn't belong to the project.
  """
  @spec get_asset(integer(), integer()) :: asset() | nil
  def get_asset(project_id, asset_id) do
    Asset
    |> where(project_id: ^project_id, id: ^asset_id)
    |> Repo.one()
  end

  @doc """
  Gets a single asset by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_asset!(integer(), integer()) :: asset()
  def get_asset!(project_id, asset_id) do
    Asset
    |> where(project_id: ^project_id, id: ^asset_id)
    |> Repo.one!()
  end

  @doc """
  Gets an asset by its storage key.
  """
  @spec get_asset_by_key(integer(), String.t()) :: asset() | nil
  def get_asset_by_key(project_id, key) do
    Asset
    |> where(project_id: ^project_id, key: ^key)
    |> Repo.one()
  end

  @doc """
  Creates an asset record.

  This only creates the database record. The actual file upload should be
  handled separately using the storage service.
  """
  @spec create_asset(project(), user(), attrs()) :: {:ok, asset()} | {:error, changeset()}
  def create_asset(%Project{} = project, %User{} = user, attrs) do
    %Asset{project_id: project.id, uploaded_by_id: user.id}
    |> Asset.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an asset record without a user (for system uploads).
  """
  @spec create_asset(project(), attrs()) :: {:ok, asset()} | {:error, changeset()}
  def create_asset(%Project{} = project, attrs) do
    %Asset{project_id: project.id}
    |> Asset.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an asset's metadata.
  """
  @spec update_asset(asset(), attrs()) :: {:ok, asset()} | {:error, changeset()}
  def update_asset(%Asset{} = asset, attrs) do
    asset
    |> Asset.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an asset.

  Note: This only deletes the database record. The actual file should be
  deleted from storage separately.
  """
  @spec delete_asset(asset()) :: {:ok, asset()} | {:error, changeset()}
  def delete_asset(%Asset{} = asset) do
    Repo.delete(asset)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking asset changes.
  """
  @spec change_asset(asset(), attrs()) :: changeset()
  def change_asset(%Asset{} = asset, attrs \\ %{}) do
    Asset.update_changeset(asset, attrs)
  end

  @doc """
  Counts assets by content type prefix for a project.

  Returns a map like:
      %{"image" => 10, "audio" => 5}
  """
  @spec count_assets_by_type(integer()) :: %{String.t() => non_neg_integer()}
  def count_assets_by_type(project_id) do
    from(a in Asset,
      where: a.project_id == ^project_id,
      group_by: fragment("split_part(?, '/', 1)", a.content_type),
      select: {fragment("split_part(?, '/', 1)", a.content_type), count(a.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the total size of all assets for a project in bytes.
  """
  @spec total_storage_size(integer()) :: non_neg_integer()
  def total_storage_size(project_id) do
    from(a in Asset,
      where: a.project_id == ^project_id,
      select: sum(a.size)
    )
    |> Repo.one() || 0
  end

  @doc """
  Generates a unique storage key for an asset.

  Format: projects/{project_id}/assets/{uuid}/{filename}
  """
  @spec generate_key(project(), String.t()) :: String.t()
  def generate_key(%Project{} = project, filename) do
    uuid = Ecto.UUID.generate()
    sanitized = sanitize_filename(filename)
    "projects/#{project.id}/assets/#{uuid}/#{sanitized}"
  end

  @doc """
  Generates a thumbnail key from an asset key.

  Format: projects/{project_id}/thumbnails/{uuid}/{filename}
  """
  @spec thumbnail_key(String.t()) :: String.t()
  def thumbnail_key(asset_key) do
    String.replace(asset_key, "/assets/", "/thumbnails/")
  end

  @doc """
  Returns a map of usage references for an asset within its project.

  Checks:
  - Flow nodes with `data->>'audio_asset_id'` matching the asset (excludes soft-deleted)
  - Sheets with `avatar_asset_id` matching the asset (excludes soft-deleted)
  - Sheets with `banner_asset_id` matching the asset (excludes soft-deleted)

  Returns:
      %{
        flow_nodes: [%{node: node, flow: flow}],
        sheet_avatars: [sheet],
        sheet_banners: [sheet]
      }
  """
  @spec get_asset_usages(integer(), integer()) :: %{
          flow_nodes: [map()],
          sheet_avatars: [Storyarn.Sheets.Sheet.t()],
          sheet_banners: [Storyarn.Sheets.Sheet.t()]
        }
  def get_asset_usages(project_id, asset_id) do
    alias Storyarn.Flows.{Flow, FlowNode}
    alias Storyarn.Sheets.Sheet

    asset_id_str = to_string(asset_id)

    flow_nodes =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id,
        where: is_nil(n.deleted_at),
        where: fragment("?->>'audio_asset_id' = ?", n.data, ^asset_id_str),
        order_by: [asc: f.name],
        select: %{node_id: n.id, node_type: n.type, flow_id: f.id, flow_name: f.name}
      )
      |> Repo.all()

    sheet_avatars =
      from(s in Sheet,
        where: s.project_id == ^project_id,
        where: is_nil(s.deleted_at),
        where: s.avatar_asset_id == ^asset_id,
        order_by: [asc: s.name]
      )
      |> Repo.all()

    sheet_banners =
      from(s in Sheet,
        where: s.project_id == ^project_id,
        where: is_nil(s.deleted_at),
        where: s.banner_asset_id == ^asset_id,
        order_by: [asc: s.name]
      )
      |> Repo.all()

    %{flow_nodes: flow_nodes, sheet_avatars: sheet_avatars, sheet_banners: sheet_banners}
  end

  @doc """
  Returns the total number of usage references for an asset.
  """
  @spec count_asset_usages(integer(), integer()) :: non_neg_integer()
  def count_asset_usages(project_id, asset_id) do
    usages = get_asset_usages(project_id, asset_id)
    length(usages.flow_nodes) + length(usages.sheet_avatars) + length(usages.sheet_banners)
  end

  @doc """
  Uploads a file from a temporary path and creates the corresponding asset record.

  Used by LiveView's `consume_uploaded_entries/3` to process file uploads directly
  from the parent LiveView (without going through the AssetUpload LiveComponent).

  Returns `{:ok, asset}` on success or `{:error, reason}` on failure.
  """
  @spec upload_and_create_asset(String.t(), Phoenix.LiveView.UploadEntry.t(), project(), user()) ::
          {:ok, asset()} | {:error, term()}
  def upload_and_create_asset(path, entry, %Project{} = project, %User{} = user) do
    alias Storyarn.Assets.ImageProcessor
    alias Storyarn.Assets.Storage

    key = generate_key(project, entry.client_name)
    content = File.read!(path)

    with {:ok, url} <- Storage.upload(key, content, entry.client_type) do
      metadata =
        if String.starts_with?(entry.client_type, "image/") and ImageProcessor.available?() do
          case ImageProcessor.get_dimensions(path) do
            {:ok, %{width: w, height: h}} -> %{"width" => w, "height" => h}
            {:error, _} -> %{}
          end
        else
          %{}
        end

      case create_asset(project, user, %{
             filename: entry.client_name,
             content_type: entry.client_type,
             size: entry.client_size,
             key: key,
             url: url,
             metadata: metadata
           }) do
        {:ok, asset} ->
          {:ok, asset}

        {:error, changeset} ->
          Storage.delete(key)
          {:error, changeset}
      end
    end
  end

  @doc """
  Sanitizes a filename for safe storage.

  Strips path components, replaces unsafe characters, downcases, and limits length.
  """
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(filename) do
    filename
    |> String.split(~r/[\/\\]/)
    |> List.last()
    |> String.replace(~r/[^\w\.\-]/, "_")
    |> String.downcase()
    |> String.slice(0, 255)
  end
end
