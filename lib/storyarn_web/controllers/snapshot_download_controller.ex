defmodule StoryarnWeb.SnapshotDownloadController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Projects
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Versioning
  alias StoryarnWeb.PrivateDownload

  @doc """
  Download a project snapshot archive.

  The archive is streamed through Storyarn only after checking that the current
  user can manage the project. No storage URL is exposed to the browser.
  """
  def download(conn, %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => snapshot_id_str}) do
    scope = conn.assigns.current_scope

    with {:ok, project, membership} <-
           Projects.get_project_by_slugs(scope, workspace_slug, project_slug),
         true <- Projects.can?(membership.role, :manage_project),
         {snapshot_id, ""} <- Integer.parse(snapshot_id_str),
         %{} = snapshot <- Versioning.get_project_snapshot(project.id, snapshot_id),
         true <- project_snapshot_key?(snapshot.storage_key, project.id) do
      filename = build_filename(project.name, snapshot)

      case PrivateDownload.send(conn, snapshot.storage_key,
             content_type: "application/gzip",
             filename: filename
           ) do
        {:ok, conn} ->
          conn

        {:error, _reason} ->
          conn |> put_status(:not_found) |> text(gettext("Snapshot file not found"))
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text(gettext("Project not found"))

      false ->
        conn |> put_status(:not_found) |> text(gettext("Project not found"))

      nil ->
        conn |> put_status(:not_found) |> text(gettext("Snapshot not found"))

      :error ->
        conn |> put_status(:bad_request) |> text(gettext("Invalid snapshot ID"))
    end
  end

  defp build_filename(project_name, snapshot) do
    slug = NameNormalizer.slugify(project_name)
    date = Calendar.strftime(snapshot.inserted_at, "%Y-%m-%d")
    "#{slug}-snapshot-v#{snapshot.version_number}-#{date}.json.gz"
  end

  defp project_snapshot_key?(key, project_id) when is_binary(key) do
    prefix = "projects/#{project_id}/snapshots/project/"

    String.starts_with?(key, prefix) and
      valid_storage_key?(key) and
      String.ends_with?(key, ".json.gz")
  end

  defp project_snapshot_key?(_key, _project_id), do: false

  defp valid_storage_key?(key) do
    key != "" and
      String.valid?(key) and
      not String.contains?(key, [<<0>>, "\\"]) and
      Enum.all?(String.split(key, "/"), &(&1 not in ["", ".", ".."]))
  end
end
