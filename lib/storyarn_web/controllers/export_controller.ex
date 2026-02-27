defmodule StoryarnWeb.ExportController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Exports
  alias Storyarn.Projects
  alias Storyarn.Shared.NameNormalizer

  @doc """
  Export a project in the requested format.

  Reads format from URL param, options from query params.
  Handles both single-file (binary) and multi-file (list of tuples) serializer output.
  """
  def export(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug,
        "format" => format_str
      }) do
    with {:ok, format} <- parse_format(format_str),
         {:ok, serializer} <- Exports.get_serializer(format),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(conn.assigns.current_scope, workspace_slug, project_slug),
         opts <- build_options(conn.params, format),
         {:ok, output} <- Exports.export_project(project, opts) do
      slug = NameNormalizer.slugify(project.name)
      send_export(conn, output, slug, serializer)
    else
      {:error, {:unknown_format, _}} ->
        conn |> put_status(:bad_request) |> text(gettext("Unknown format"))

      :error ->
        conn |> put_status(:bad_request) |> text(gettext("Invalid format"))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text(gettext("Not found"))

      _ ->
        conn |> put_status(:unprocessable_entity) |> text(gettext("Export failed"))
    end
  end

  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  # Single-file output (binary string)
  defp send_export(conn, output, slug, serializer) when is_binary(output) do
    ext = serializer.file_extension()
    filename = "#{slug}.#{ext}"

    conn
    |> put_resp_content_type(serializer.content_type())
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, output)
  end

  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  # Multi-file output (list of {filename, content} tuples) — send main file
  defp send_export(conn, [{filename, content} | _rest], _slug, serializer) do
    conn
    |> put_resp_content_type(serializer.content_type())
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, content)
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
    %{
      format: format,
      validate_before_export: params["validate"] != "false",
      pretty_print: params["pretty"] != "false",
      include_sheets: params["sheets"] != "false",
      include_flows: params["flows"] != "false",
      include_scenes: params["scenes"] != "false",
      include_screenplays: params["screenplays"] != "false",
      include_localization: params["localization"] != "false",
      include_assets: parse_asset_mode(params["assets"])
    }
  end

  defp parse_asset_mode("embedded"), do: :embedded
  defp parse_asset_mode("bundled"), do: :bundled
  defp parse_asset_mode(_), do: :references
end
