defmodule StoryarnWeb.UploadController do
  @moduledoc """
  Handles multipart file uploads for project assets.

  Receives files via standard multipart/form-data POST instead of base64
  through the LiveView channel, avoiding payload size limits on longpoll.
  """

  use StoryarnWeb, :controller

  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Projects

  def create(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug,
        "file" => %Plug.Upload{} = upload
      }) do
    scope = conn.assigns.current_scope

    with {:ok, project, membership} <-
           Projects.get_project_by_slugs(scope, workspace_slug, project_slug),
         true <- Projects.can?(membership.role, :edit_content),
         binary_data <- File.read!(upload.path),
         :ok <- Billing.can_upload_asset_for_project?(project, byte_size(binary_data)),
         {:ok, asset} <-
           Assets.upload_binary_and_create_asset(
             binary_data,
             %{
               filename: upload.filename,
               content_type: upload.content_type,
               purpose: parse_purpose(conn.params["purpose"])
             },
             project,
             scope.user
           ) do
      json(conn, %{id: asset.id, url: asset.url})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      false ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :limit_reached, _} ->
        conn |> put_status(:payment_required) |> json(%{error: "storage_limit_reached"})

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "upload_failed"})
    end
  end

  defp parse_purpose("avatar"), do: :avatar
  defp parse_purpose("banner"), do: :banner
  defp parse_purpose("gallery"), do: :gallery
  defp parse_purpose(_), do: :general
end
