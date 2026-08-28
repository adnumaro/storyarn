defmodule StoryarnWeb.ExportController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Projects

  require Logger

  @temporary_export_filename ~r/\Astoryarn-export-\d+\.zip\z/

  @doc """
  Export a project in the requested format.

  Reads format from URL param, options from query params.
  Handles both single-file (binary) and multi-file (list of tuples) serializer output.
  """
  def export(conn, %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "format" => format_str}) do
    with {:ok, format} <- parse_format(format_str),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(conn.assigns.current_scope, workspace_slug, project_slug),
         {:ok, opts} <- build_options(conn.params, format),
         {:ok, artifact} <-
           Projects.prepare_project_export(conn.assigns.current_scope, project, opts) do
      slug = Projects.slugify_project_name(project.name)
      send_export(conn, artifact, slug)
    else
      {:error, {:unknown_format, _}} ->
        conn |> put_status(:bad_request) |> text(gettext("Unknown format"))

      :error ->
        conn |> put_status(:bad_request) |> text(gettext("Invalid format"))

      {:error, :invalid_localization_policy} ->
        conn |> put_status(:bad_request) |> text(gettext("Invalid localization policy"))

      {:error, :unauthorized} ->
        conn |> put_status(:forbidden) |> text(gettext("You do not have permission to export this project"))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text(gettext("Not found"))

      {:error, {:export_too_large, _details}} ->
        conn |> put_status(413) |> text(gettext("Export is too large"))

      {:error, {:validation_failed, _result}} ->
        conn
        |> put_resp_header("x-storyarn-export-error", "validation")
        |> put_status(:unprocessable_entity)
        |> text(gettext("Export failed"))

      _ ->
        conn
        |> put_resp_header("x-storyarn-export-error", "serialization")
        |> put_status(:unprocessable_entity)
        |> text(gettext("Export failed"))
    end
  end

  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  # Single-file output (binary string)
  defp send_export(conn, %{delivery: :single, body: output, extension: extension, content_type: content_type}, slug)
       when is_binary(output) and is_binary(extension) and is_binary(content_type) do
    filename = "#{slug}.#{extension}"

    case validate_export_size(byte_size(output), Projects.max_sync_project_export_bytes()) do
      :ok ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_resp(200, output)

      {:error, {:export_too_large, _details}} ->
        conn |> put_status(413) |> text(gettext("Export is too large"))
    end
  end

  # The ZIP path is generated internally by zip_files_to_disk/1 from
  # System.tmp_dir!/0 and a unique integer; it never contains request input.
  # sobelow_skip ["Traversal.FileModule", "XSS.ContentType", "XSS.SendResp"]
  # Multi-file output (list of {filename, content} tuples)
  defp send_export(
         conn,
         %{delivery: :archive, entries: files, format: format, extension: "zip", content_type: content_type},
         slug
       )
       when is_list(files) and is_atom(format) and is_binary(content_type) do
    filename = "#{slug}-#{format}.zip"

    case zip_files_to_disk(files) do
      {:ok, zip_path} ->
        try do
          conn
          |> put_resp_content_type(content_type, nil)
          |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
          |> send_chunked(200)
          |> stream_zip_file(zip_path)
        after
          remove_temporary_zip(zip_path)
        end

      {:error, {:export_too_large, _details}} ->
        conn |> put_status(413) |> text(gettext("Export is too large"))

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> text(gettext("Export failed"))
    end
  end

  defp zip_files_to_disk(files) do
    max_bytes = Projects.max_sync_project_export_bytes()

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

      zip_creator = zip_creator()

      case zip_creator.(String.to_charlist(zip_path), entries) do
        {:ok, _zip_filename} ->
          {:ok, zip_path}

        {:error, _reason} = error ->
          remove_temporary_zip(zip_path)
          error
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

  defp zip_creator do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:zip_creator, &:zip.create/2)
  end

  # The path is constrained again at the deletion boundary so future callers
  # cannot turn this cleanup helper into an arbitrary file deletion primitive.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_temporary_zip(zip_path) do
    case safe_temporary_zip_path(zip_path) do
      {:ok, safe_path} ->
        case File.rm(safe_path) do
          :ok ->
            :ok

          {:error, :enoent} ->
            :ok

          {:error, reason} ->
            Logger.warning("Temporary export archive cleanup failed path=#{inspect(safe_path)} reason=#{inspect(reason)}")
        end

      {:error, :invalid_temporary_zip_path} ->
        Logger.warning("Refusing to remove invalid temporary export archive path=#{inspect(zip_path)}")
    end
  end

  defp safe_temporary_zip_path(zip_path) when is_binary(zip_path) do
    tmp_dir = Path.expand(System.tmp_dir!())
    expanded_path = Path.expand(zip_path)
    filename = Path.basename(expanded_path)

    if Path.dirname(expanded_path) == tmp_dir and Regex.match?(@temporary_export_filename, filename) do
      {:ok, expanded_path}
    else
      {:error, :invalid_temporary_zip_path}
    end
  end

  defp safe_temporary_zip_path(_zip_path), do: {:error, :invalid_temporary_zip_path}

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

  # Matched against the valid list as a string rather than through
  # `String.to_existing_atom/1`. That call raised whenever the format's atom was
  # not yet in the VM's table, and every format except the old `:storyarn` is
  # only interned once `ExportOptions` loads — `:storyarn` happened to always
  # exist because it is also the OTP application name, which is what kept the
  # bug hidden. Comparing strings has no such dependency and cannot raise.
  defp parse_format(format_str) do
    case Enum.find(Projects.valid_project_export_formats(), &(Atom.to_string(&1) == format_str)) do
      nil -> :error
      format -> {:ok, format}
    end
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
