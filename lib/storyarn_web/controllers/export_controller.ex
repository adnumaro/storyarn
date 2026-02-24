defmodule StoryarnWeb.ExportController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Exports
  alias Storyarn.Projects
  alias Storyarn.Shared.NameNormalizer

  def storyarn(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug
      }) do
    with {:ok, project, _membership} <-
           Projects.get_project_by_slugs(conn.assigns.current_scope, workspace_slug, project_slug),
         {:ok, output} <-
           Exports.export_project(project, %{format: :storyarn, validate_before_export: false}) do
      slug = NameNormalizer.slugify(project.name)
      filename = "#{slug}.storyarn.json"

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, output)
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> text(gettext("Not found"))
    end
  end
end
