defmodule StoryarnWeb.ExportController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Exports
  alias Storyarn.Projects
  alias Storyarn.Shared.NameNormalizer

  @default_max_sync_export_bytes 64 * 1024 * 1024

  @doc """
  Export a project in the requested format.

  Reads format from URL param, options from query params.
  Handles both single-file (binary) and multi-file (list of tuples) serializer output.
  """
  def export(conn, %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "format" => format_str}) do
    with {:ok, format} <- parse_format(format_str),
         {:ok, serializer} <- Exports.get_serializer(format),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(conn.assigns.current_scope, workspace_slug, project_slug),
         {:ok, opts} <- build_options(conn.params, format),
         {:ok, output} <- Exports.export_project(project, opts) do
      slug = NameNormalizer.slugify(project.name)
      send_export(conn, output, slug, format, serializer)
    else
      {:error, {:unknown_format, _}} ->
        conn |> put_status(:bad_request) |> text(gettext("Unknown format"))

      :error ->
        conn |> put_status(:bad_request) |> text(gettext("Invalid format"))

      {:error, :invalid_localization_policy} ->
        conn |> put_status(:bad_request) |> text(gettext("Invalid localization policy"))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text(gettext("Not found"))

      {:error, {:export_too_large, _details}} ->
        conn |> put_status(413) |> text(gettext("Export is too large"))

      _ ->
        conn |> put_status(:unprocessable_entity) |> text(gettext("Export failed"))
    end
  end

  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  # Single-file output (binary string)
  defp send_export(conn, output, slug, _format, serializer) when is_binary(output) do
    ext = serializer.file_extension()
    filename = "#{slug}.#{ext}"

    conn
    |> put_resp_content_type(serializer.content_type())
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, output)
  end

  # The ZIP path is generated internally by zip_files_to_disk/1 from
  # System.tmp_dir!/0 and a unique integer; it never contains request input.
  # sobelow_skip ["Traversal.FileModule", "XSS.ContentType", "XSS.SendResp"]
  # Multi-file output (list of {filename, content} tuples)
  defp send_export(conn, files, slug, format, _serializer) when is_list(files) do
    filename = "#{slug}-#{format}.zip"

    case zip_files_to_disk(files) do
      {:ok, zip_path} ->
        try do
          conn
          |> put_resp_content_type("application/zip", nil)
          |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
          |> send_chunked(200)
          |> stream_zip_file(zip_path)
        after
          File.rm(zip_path)
        end

      {:error, {:export_too_large, _details}} ->
        conn |> put_status(413) |> text(gettext("Export is too large"))

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> text(gettext("Export failed"))
    end
  end

  defp zip_files_to_disk(files) do
    max_bytes =
      Application.get_env(
        :storyarn,
        :max_sync_export_bytes,
        @default_max_sync_export_bytes
      )

    with {:ok, total_bytes} <- export_size(files),
         :ok <- validate_export_size(total_bytes, max_bytes) do
      zip_path =
        Path.join(
          System.tmp_dir!(),
          "storyarn-export-#{System.unique_integer([:positive, :monotonic])}.zip"
        )

      entries =
        Enum.map(files, fn {entry_filename, content} ->
          {String.to_charlist(entry_filename), IO.iodata_to_binary(content)}
        end)

      case :zip.create(String.to_charlist(zip_path), entries) do
        {:ok, _zip_filename} -> {:ok, zip_path}
        {:error, _reason} = error -> error
      end
    end
  end

  defp export_size(files) do
    Enum.reduce_while(files, {:ok, 0}, fn
      {entry_filename, content}, {:ok, total} when is_binary(entry_filename) ->
        try do
          {:cont, {:ok, total + IO.iodata_length(content)}}
        rescue
          ArgumentError -> {:halt, {:error, :invalid_export_content}}
        end

      _entry, _acc ->
        {:halt, {:error, :invalid_export_content}}
    end)
  end

  defp validate_export_size(total_bytes, max_bytes) when total_bytes <= max_bytes, do: :ok

  defp validate_export_size(total_bytes, max_bytes),
    do: {:error, {:export_too_large, %{bytes: total_bytes, max_bytes: max_bytes}}}

  # zip_path is the internally generated path returned by zip_files_to_disk/1.
  # sobelow_skip ["Traversal.FileModule"]
  defp stream_zip_file(conn, zip_path) do
    zip_path
    |> File.stream!(64 * 1024, [])
    |> Enum.reduce_while(conn, fn data, conn ->
      case chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, halt(conn)}
      end
    end)
  end

  defp parse_format(format_str) do
    format = String.to_existing_atom(format_str)

    if format in Exports.valid_export_formats() do
      {:ok, format}
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  defp build_options(params, format) do
    with {:ok, localization_policy} <- parse_localization_policy(params["localization_policy"]) do
      {:ok,
       %{
         format: format,
         validate_before_export: params["validate"] != "false",
         pretty_print: params["pretty"] != "false",
         include_sheets: params["sheets"] != "false",
         include_flows: params["flows"] != "false",
         include_scenes: params["scenes"] != "false",
         include_screenplays: params["screenplays"] != "false",
         include_localization: params["localization"] != "false",
         localization_policy: localization_policy,
         include_assets: parse_asset_mode(params["assets"])
       }}
    end
  end

  defp parse_asset_mode("embedded"), do: :embedded
  defp parse_asset_mode("bundled"), do: :bundled
  defp parse_asset_mode(_), do: :references

  defp parse_localization_policy(nil), do: {:ok, :release}
  defp parse_localization_policy("release"), do: {:ok, :release}
  defp parse_localization_policy("preview"), do: {:ok, :preview}
  defp parse_localization_policy(_policy), do: {:error, :invalid_localization_policy}
end
