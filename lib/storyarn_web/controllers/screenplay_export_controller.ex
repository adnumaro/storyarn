defmodule StoryarnWeb.ScreenplayExportController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Projects
  alias Storyarn.Screenplays
  alias Storyarn.Shared.NameNormalizer

  def fountain(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug,
        "id" => id
      }) do
    if conn.assigns.current_scope.user.is_super_admin do
      export_fountain(conn, workspace_slug, project_slug, id)
    else
      conn
      |> put_status(:not_found)
      |> text(dgettext("screenplays", "Not found"))
    end
  end

  defp export_fountain(conn, workspace_slug, project_slug, id) do
    with {:ok, project, _membership} <-
           Projects.get_project_by_slugs(conn.assigns.current_scope, workspace_slug, project_slug),
         screenplay when not is_nil(screenplay) <-
           Screenplays.get_screenplay(project.id, id) do
      elements = Screenplays.list_elements(screenplay.id)
      text = Screenplays.export_fountain(elements)

      slug =
        case NameNormalizer.slugify(screenplay.name) do
          "" -> "screenplay"
          normalized -> normalized
        end

      filename = String.slice(slug, 0, 200) <> ".fountain"

      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, text)
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> text(dgettext("screenplays", "Not found"))
    end
  end
end
