defmodule Storyarn.Workspaces.WorkspaceBanner do
  @moduledoc """
  Workspace-owned lifecycle for private banner images.

  Authorization, validation, persistence, and storage compensation live here.
  Storage is an opaque technical port and never decides Workspace ownership.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Workspaces.BannerCleanupQueue
  alias Storyarn.Workspaces.BannerStorage
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceCrud
  alias Storyarn.Workspaces.WorkspaceMembership

  require Logger

  @upload_limits Application.compile_env!(:storyarn, __MODULE__)
  @max_file_size Keyword.fetch!(@upload_limits, :max_file_size)
  @accepted_content_types ~w(image/jpeg image/png image/gif image/webp)
  @content_type_by_loader %{
    "jpegload" => "image/jpeg",
    "pngload" => "image/png",
    "gifload" => "image/gif",
    "nsgifload" => "image/gif",
    "webpload" => "image/webp"
  }

  @type scope :: %{user: %{id: integer()}}
  @type upload_attrs :: %{
          required(:filename) => String.t(),
          required(:content_type) => String.t(),
          required(:data) => String.t()
        }
  @type banner_error ::
          :not_found
          | :unauthorized
          | :invalid_banner_upload
          | {:workspace_banner_cleanup_enqueue_failed, term()}
          | {:workspace_banner_cleanup_deferred, term(), term()}
          | {:workspace_banner_storage_failed, term()}
          | {:workspace_banner_update_failed, term()}
          | {:workspace_banner_update_failed_with_cleanup_required, term(), String.t(), term()}

  @spec upload(scope(), pos_integer(), upload_attrs(), keyword()) ::
          {:ok, Workspace.t()} | {:error, banner_error()}
  def upload(scope, workspace_id, attrs, opts \\ [])

  def upload(%{user: %{id: user_id}} = scope, workspace_id, attrs, opts)
      when is_integer(user_id) and is_integer(workspace_id) and workspace_id > 0 and is_map(attrs) and is_list(opts) do
    with {:ok, workspace} <- authorize(scope, workspace_id),
         {:ok, upload} <- validate_upload(attrs),
         key = new_banner_key(workspace, upload.filename),
         {:ok, url} <- upload_to_owned_key(key, upload.binary, upload.content_type, opts) do
      persist_uploaded_banner(scope, workspace_id, key, url, opts)
    end
  end

  def upload(_scope, _workspace_id, _attrs, _opts), do: {:error, :unauthorized}

  @spec remove(scope(), pos_integer(), keyword()) ::
          {:ok, Workspace.t()} | {:error, banner_error()}
  def remove(scope, workspace_id, opts \\ [])

  def remove(%{user: %{id: user_id}} = scope, workspace_id, opts)
      when is_integer(user_id) and is_integer(workspace_id) and workspace_id > 0 and is_list(opts) do
    with {:ok, _workspace} <- authorize(scope, workspace_id) do
      safe_persist_banner_url(scope, workspace_id, nil, nil, opts)
    end
  end

  def remove(_scope, _workspace_id, _opts), do: {:error, :unauthorized}

  @spec get(scope(), String.t(), keyword()) ::
          {:ok, %{key: String.t(), content_type: String.t()}} | {:error, :not_found}
  def get(scope, workspace_slug, opts \\ [])

  def get(%{user: %{id: user_id}} = scope, workspace_slug, opts)
      when is_integer(user_id) and is_binary(workspace_slug) and workspace_slug != "" and is_list(opts) do
    with {:ok, workspace, _membership} <- WorkspaceCrud.get_workspace_by_slug(scope, workspace_slug),
         {:ok, key} <- stored_banner_key(workspace, opts),
         content_type when content_type in @accepted_content_types <- MIME.from_path(key) do
      {:ok, %{key: key, content_type: content_type}}
    else
      _ -> {:error, :not_found}
    end
  end

  def get(_scope, _workspace_slug, _opts), do: {:error, :not_found}

  @doc false
  @spec prepare_hard_delete(Workspace.t(), keyword()) :: :ok | {:error, term()}
  def prepare_hard_delete(%Workspace{} = workspace, opts \\ []) when is_list(opts) do
    schedule_previous_cleanup(workspace, nil, opts)
  end

  @doc false
  @spec perform_cleanup(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def perform_cleanup(workspace_slug, storage_key, opts \\ [])

  def perform_cleanup(workspace_slug, storage_key, opts)
      when is_binary(workspace_slug) and is_binary(storage_key) and is_list(opts) do
    if owned_banner_key?(workspace_slug, storage_key),
      do: safe_storage_delete(storage_key, opts),
      else: {:error, :invalid_banner_key}
  end

  def perform_cleanup(_workspace_slug, _storage_key, _opts), do: {:error, :invalid_banner_key}

  defp authorize(scope, workspace_id) do
    case Memberships.authorize(scope, workspace_id, :manage_workspace) do
      {:ok, %Workspace{} = workspace, _membership} -> {:ok, workspace}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_upload(attrs) do
    filename = value(attrs, :filename)
    content_type = value(attrs, :content_type)
    data = value(attrs, :data)

    with true <- valid_upload_strings?(filename, content_type, data),
         {:ok, safe_filename} <- sanitize_filename(filename),
         true <- content_type in @accepted_content_types,
         true <- MIME.from_path(safe_filename) == content_type,
         [header, encoded] <- String.split(data, ",", parts: 2),
         true <- header == "data:#{content_type};base64",
         :ok <- validate_encoded_size(encoded),
         {:ok, binary} <- Base.decode64(encoded),
         true <- byte_size(binary) > 0 and byte_size(binary) <= @max_file_size,
         {:ok, ^content_type} <- content_type_from_binary(binary) do
      {:ok, %{filename: safe_filename, content_type: content_type, binary: binary}}
    else
      _ -> {:error, :invalid_banner_upload}
    end
  end

  defp valid_upload_strings?(filename, content_type, data) do
    is_binary(filename) and String.valid?(filename) and String.trim(filename) != "" and
      byte_size(filename) <= 255 and is_binary(content_type) and String.valid?(content_type) and
      is_binary(data) and String.valid?(data)
  end

  defp sanitize_filename(filename) do
    sanitized =
      filename
      |> String.split(~r/[\/\\]/)
      |> List.last()
      |> String.replace(~r/[^\w\.\-]/u, "_")
      |> String.downcase()
      |> String.slice(0, 180)

    if sanitized in ["", ".", ".."],
      do: {:error, :invalid_filename},
      else: {:ok, sanitized}
  end

  defp validate_encoded_size(encoded) when is_binary(encoded) do
    max_encoded_size = 4 * div(@max_file_size + 2, 3)
    if byte_size(encoded) <= max_encoded_size, do: :ok, else: {:error, :too_large}
  end

  defp validate_encoded_size(_encoded), do: {:error, :too_large}

  defp content_type_from_binary(binary) do
    with {:ok, image} <- Image.open(binary),
         {:ok, loader} <- Vix.Vips.Image.header_value(image, "vips-loader"),
         content_type when is_binary(content_type) <- content_type_for_loader(loader) do
      {:ok, content_type}
    else
      _ -> {:error, :unsupported_image}
    end
  end

  defp content_type_for_loader(loader) when is_binary(loader) do
    loader
    |> String.replace_suffix("_buffer", "")
    |> then(&Map.get(@content_type_by_loader, &1))
  end

  defp content_type_for_loader(_loader), do: nil

  defp new_banner_key(workspace, filename) do
    "workspaces/#{workspace.slug}/banner/#{Ecto.UUID.generate()}#{Path.extname(filename)}"
  end

  defp upload_to_owned_key(key, binary, content_type, opts) do
    case safe_storage_upload(key, binary, content_type, opts) do
      {:ok, url} when is_binary(url) and url != "" ->
        validate_uploaded_url(url, key, opts)

      {:error, reason} ->
        {:error, {:workspace_banner_storage_failed, reason}}

      result ->
        {:error, {:workspace_banner_storage_failed, {:unexpected_result, result}}}
    end
  end

  defp validate_uploaded_url(url, key, opts) do
    case safe_storage_key_from_url(url, opts) do
      {:ok, ^key} ->
        {:ok, url}

      result ->
        cleanup_uploaded_key(key, {:invalid_uploaded_url, result}, opts)
    end
  end

  defp persist_uploaded_banner(scope, workspace_id, key, url, opts) do
    case safe_persist_banner_url(scope, workspace_id, url, key, opts) do
      {:ok, workspace} ->
        {:ok, workspace}

      {:error, reason} ->
        compensate_failed_update(key, reason, opts)
    end
  end

  defp safe_persist_banner_url(scope, workspace_id, banner_url, current_key, opts) do
    persist_banner_url(scope, workspace_id, banner_url, current_key, opts)
  rescue
    error -> {:error, {:workspace_banner_update_failed, error}}
  catch
    kind, reason -> {:error, {:workspace_banner_update_failed, {kind, reason}}}
  end

  defp persist_banner_url(scope, workspace_id, banner_url, current_key, opts) do
    Repo.transact(fn ->
      with {:ok, workspace} <- lock_authorized_workspace(scope, workspace_id),
           {:ok, updated_workspace} <- update_banner_url(workspace, banner_url),
           :ok <- schedule_previous_cleanup(workspace, current_key, opts) do
        {:ok, updated_workspace}
      end
    end)
  end

  defp lock_authorized_workspace(%{user: %{id: user_id}}, workspace_id) do
    query =
      from(workspace in Workspace,
        join: membership in WorkspaceMembership,
        on: membership.workspace_id == workspace.id,
        where: workspace.id == ^workspace_id and membership.user_id == ^user_id,
        select: {workspace, membership},
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      {%Workspace{} = workspace, %WorkspaceMembership{role: role}} ->
        if WorkspaceMembership.can?(role, :manage_workspace),
          do: {:ok, workspace},
          else: {:error, :unauthorized}

      nil ->
        {:error, :unauthorized}
    end
  end

  defp update_banner_url(workspace, banner_url) do
    case workspace |> Workspace.banner_changeset(%{banner_url: banner_url}) |> Repo.update() do
      {:ok, updated_workspace} -> {:ok, updated_workspace}
      {:error, reason} -> {:error, {:workspace_banner_update_failed, reason}}
    end
  end

  defp compensate_failed_update(key, reason, opts) do
    case safe_storage_delete(key, opts) do
      :ok ->
        {:error, reason}

      {:error, cleanup_reason} ->
        defer_failed_cleanup(key, reason, cleanup_reason, opts)

      result ->
        defer_failed_cleanup(key, reason, {:unexpected_result, result}, opts)
    end
  end

  defp cleanup_uploaded_key(key, reason, opts) do
    case safe_storage_delete(key, opts) do
      :ok ->
        {:error, {:workspace_banner_storage_failed, reason}}

      {:error, cleanup_reason} ->
        defer_failed_cleanup(key, {:workspace_banner_storage_failed, reason}, cleanup_reason, opts)

      result ->
        defer_failed_cleanup(
          key,
          {:workspace_banner_storage_failed, reason},
          {:unexpected_result, result},
          opts
        )
    end
  end

  defp defer_failed_cleanup(key, reason, cleanup_reason, opts) do
    with {:ok, workspace_slug} <- workspace_slug_from_owned_key(key),
         :ok <- BannerCleanupQueue.enqueue(workspace_slug, key, opts) do
      {:error, {:workspace_banner_cleanup_deferred, reason, cleanup_reason}}
    else
      {:error, queue_reason} ->
        Logger.error(
          "Workspace banner cleanup could not be persisted " <>
            "object=#{inspect(Path.basename(key))} reason=#{inspect(queue_reason)}"
        )

        {:error,
         {:workspace_banner_update_failed_with_cleanup_required, reason, key,
          %{delete: cleanup_reason, enqueue: queue_reason}}}
    end
  end

  defp workspace_slug_from_owned_key(key) when is_binary(key) do
    case String.split(key, "/", parts: 4) do
      ["workspaces", workspace_slug, "banner", filename]
      when workspace_slug != "" and filename != "" ->
        if owned_banner_key?(workspace_slug, key),
          do: {:ok, workspace_slug},
          else: {:error, :invalid_banner_key}

      _invalid ->
        {:error, :invalid_banner_key}
    end
  end

  defp workspace_slug_from_owned_key(_key), do: {:error, :invalid_banner_key}

  defp schedule_previous_cleanup(previous_workspace, current_key, opts) do
    case stored_banner_key(previous_workspace, opts) do
      {:ok, ^current_key} ->
        :ok

      {:ok, previous_key} ->
        case BannerCleanupQueue.enqueue(previous_workspace.slug, previous_key, opts) do
          :ok -> :ok
          {:error, reason} -> {:error, {:workspace_banner_cleanup_enqueue_failed, reason}}
        end

      {:error, :no_banner} ->
        :ok

      {:error, reason} ->
        Logger.warning("Workspace banner cleanup skipped for an untrusted stored URL: #{inspect(reason)}")
        :ok
    end
  end

  defp stored_banner_key(%Workspace{banner_url: nil}, _opts), do: {:error, :no_banner}
  defp stored_banner_key(%Workspace{banner_url: ""}, _opts), do: {:error, :no_banner}

  defp stored_banner_key(%Workspace{banner_url: url} = workspace, opts) when is_binary(url) do
    with {:ok, key} <- safe_storage_key_from_url(url, opts),
         true <- owned_banner_key?(workspace, key) do
      {:ok, key}
    else
      _ -> {:error, :invalid_banner_url}
    end
  end

  defp stored_banner_key(_workspace, _opts), do: {:error, :invalid_banner_url}

  defp owned_banner_key?(%Workspace{slug: slug}, key), do: owned_banner_key?(slug, key)

  defp owned_banner_key?(slug, key) when is_binary(slug) and is_binary(key) do
    prefix = "workspaces/#{slug}/banner/"

    with true <- String.valid?(key),
         true <- String.starts_with?(key, prefix),
         filename = String.replace_prefix(key, prefix, ""),
         true <- filename not in ["", ".", ".."],
         false <- String.contains?(filename, [<<0>>, "/", "\\"]) do
      true
    else
      _ -> false
    end
  end

  defp owned_banner_key?(_workspace_or_slug, _key), do: false

  defp safe_storage_upload(key, binary, content_type, opts) do
    BannerStorage.upload(key, binary, content_type, opts)
  rescue
    error -> {:error, {:storage_exception, error}}
  end

  defp safe_storage_delete(key, opts) do
    case BannerStorage.delete(key, opts) do
      :ok -> :ok
      {:error, _reason} = error -> error
      result -> {:error, {:unexpected_storage_delete_result, result}}
    end
  rescue
    error -> {:error, {:storage_exception, error}}
  end

  defp safe_storage_key_from_url(url, opts) do
    case BannerStorage.key_from_url(url, opts) do
      {:ok, key} when is_binary(key) -> {:ok, key}
      {:error, _reason} = error -> error
      result -> {:error, {:unexpected_key_from_url_result, result}}
    end
  rescue
    error -> {:error, {:storage_exception, error}}
  end

  defp value(attrs, key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end
end
