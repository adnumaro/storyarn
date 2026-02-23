defmodule StoryarnWeb.LocalizationExportController do
  use StoryarnWeb, :controller

  alias Storyarn.Localization
  alias Storyarn.Projects

  def export(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug,
        "format" => format,
        "locale" => locale
      }) do
    scope = conn.assigns.current_scope

    case Projects.get_project_by_slugs(scope, workspace_slug, project_slug) do
      {:ok, project, _membership} ->
        opts = [locale_code: locale]
        opts = maybe_add_filter(opts, :status, conn.params["status"])
        opts = maybe_add_filter(opts, :source_type, conn.params["source_type"])

        case format do
          "xlsx" ->
            {:ok, binary} = Localization.export_xlsx(project.id, opts)
            filename = "#{project.slug}_translations_#{locale}.xlsx"

            conn
            |> put_resp_content_type(
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            )
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, binary)

          "csv" ->
            {:ok, csv} = Localization.export_csv(project.id, opts)
            filename = "#{project.slug}_translations_#{locale}.csv"

            conn
            |> put_resp_content_type("text/csv")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, csv)

          _ ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Unsupported format. Use 'xlsx' or 'csv'."})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})
    end
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)
end
