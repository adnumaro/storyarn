defmodule StoryarnWeb.ScreenplayExportController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Projects
  alias Storyarn.Screenplays

  def fountain(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug,
        "id" => id
      }) do
    with {:ok, project, _membership} <-
           Projects.get_project_by_slugs(conn.assigns.current_scope, workspace_slug, project_slug),
         screenplay when not is_nil(screenplay) <-
           Screenplays.get_screenplay(project.id, id) do
      elements = Screenplays.list_elements(screenplay.id)
      text = Screenplays.export_fountain(elements)
      filename = slugify(screenplay.name) <> ".fountain"

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

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "screenplay"
      slug -> slug
    end
  end

  defp slugify(_), do: "screenplay"
end
