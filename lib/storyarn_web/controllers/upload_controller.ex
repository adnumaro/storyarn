defmodule StoryarnWeb.UploadController do
  @moduledoc """
  Handles multipart file uploads for project assets.

  Receives files via standard multipart/form-data POST instead of base64
  through the LiveView channel, avoiding payload size limits on longpoll.
  """

  use StoryarnWeb, :controller

  alias Storyarn.Assets
  alias Storyarn.Assets.UploadPolicy
  alias Storyarn.Billing
  alias Storyarn.Projects
  alias StoryarnWeb.PrivateMedia

  def inspect_upload(conn, %{"workspace_slug" => workspace_slug, "project_slug" => project_slug}) do
    scope = conn.assigns.current_scope

    with {:ok, project, membership} <-
           Projects.get_project_by_slugs(scope, workspace_slug, project_slug),
         true <- Projects.can?(membership.role, :edit_content),
         {:ok, decision} <- Assets.inspect_upload(project, conn.params) do
      json(conn, encode_decision(decision))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      false ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :limit_reached, _} ->
        conn |> put_status(:payment_required) |> json(%{error: "storage_limit_reached"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def materialize(conn, %{"workspace_slug" => workspace_slug, "project_slug" => project_slug}) do
    scope = conn.assigns.current_scope

    with {:ok, project, membership} <-
           Projects.get_project_by_slugs(scope, workspace_slug, project_slug),
         true <- Projects.can?(membership.role, :edit_content),
         {:ok, asset, meta} <- Assets.materialize_upload_variant(project, scope.user, conn.params) do
      json(conn, upload_response(asset, meta))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      false ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :limit_reached, _} ->
        conn |> put_status(:payment_required) |> json(%{error: "storage_limit_reached"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def create(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug,
        "file" => %Plug.Upload{} = upload
      }) do
    scope = conn.assigns.current_scope

    with {:ok, project, membership} <-
           Projects.get_project_by_slugs(scope, workspace_slug, project_slug),
         true <- Projects.can?(membership.role, :edit_content),
         {:ok, binary_data} <- read_upload(upload),
         :ok <- Billing.can_upload_asset_for_project?(project, byte_size(binary_data)),
         {:ok, asset} <-
           create_asset(binary_data, upload, conn.params["purpose"], project, scope.user) do
      json(conn, upload_response(asset))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      false ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :limit_reached, _} ->
        conn |> put_status(:payment_required) |> json(%{error: "storage_limit_reached"})

      {:error, :too_large} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "too_large"})

      {:error, :not_accepted} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "not_accepted"})

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "upload_failed"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: "missing_file"})
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_upload(%Plug.Upload{path: path}) do
    with {:ok, path} <- safe_upload_path(path),
         {:ok, binary_data} <- File.read(path) do
      {:ok, binary_data}
    else
      {:error, reason} -> {:error, {:unreadable_upload, reason}}
    end
  end

  defp safe_upload_path(path) when is_binary(path) do
    tmp_dir = Path.expand(System.tmp_dir!())
    path = Path.expand(path)

    with true <- path_inside?(path, tmp_dir),
         true <- File.regular?(path) do
      {:ok, path}
    else
      false -> {:error, :invalid_upload_path}
    end
  end

  defp safe_upload_path(_path), do: {:error, :invalid_upload_path}

  defp path_inside?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end

  defp create_asset(binary_data, upload, purpose_param, project, user) do
    purpose = UploadPolicy.parse_purpose(purpose_param)

    attrs = %{
      filename: upload.filename,
      content_type: upload.content_type,
      purpose: purpose
    }

    if UploadPolicy.supported_purpose?(purpose) do
      with {:ok, asset, _meta} <- Assets.upload_binary_for_purpose(binary_data, attrs, project, user) do
        {:ok, asset}
      end
    else
      Assets.upload_binary_and_create_asset(binary_data, attrs, project, user)
    end
  end

  defp encode_decision(decision) do
    %{
      action: to_string(decision.action),
      source_exists: decision.source_exists,
      variant_exists: decision.variant_exists,
      requires_variant: decision.requires_variant,
      variant_profile: decision.variant_profile,
      target: decision.target,
      asset_id: decision.asset_id
    }
  end

  defp upload_response(asset, meta \\ %{}) do
    %{
      id: asset.id,
      url: PrivateMedia.asset_url(asset),
      reused: Map.get(meta, :reused, false),
      action: meta |> Map.get(:action) |> maybe_to_string()
    }
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)
end
