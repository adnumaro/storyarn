defmodule StoryarnWeb.UploadControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.Scope
  alias StoryarnWeb.UploadController

  describe "create/2" do
    setup :register_and_log_in_user

    test "returns an error when file is missing", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UploadController.create(%{
          "workspace_slug" => workspace.slug,
          "project_slug" => project.slug,
          "purpose" => "image"
        })

      assert %{"error" => "missing_file"} = json_response(conn, 422)
    end

    test "returns an upload error when the temporary file cannot be read", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      upload = %Plug.Upload{
        path: "/tmp/storyarn-missing-upload-#{System.unique_integer([:positive])}.png",
        filename: "missing.png",
        content_type: "image/png"
      }

      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UploadController.create(%{
          "workspace_slug" => workspace.slug,
          "project_slug" => project.slug,
          "purpose" => "image",
          "file" => upload
        })

      assert %{"error" => "upload_failed"} = json_response(conn, 422)
    end
  end
end
