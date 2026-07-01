defmodule StoryarnWeb.UploadControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets
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

    test "rejects upload paths outside the system temporary directory", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      path = Path.join(["test", "tmp", "unsafe-upload-#{System.unique_integer([:positive])}.png"])

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "not really a png")

      on_exit(fn -> File.rm(path) end)

      upload = %Plug.Upload{
        path: path,
        filename: "unsafe.png",
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

    test "rejects generic SVG uploads", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      path =
        Path.join(
          System.tmp_dir!(),
          "storyarn-svg-upload-#{System.unique_integer([:positive])}.svg"
        )

      File.write!(
        path,
        ~S"""
        <svg xmlns="http://www.w3.org/2000/svg"><script>alert(document.domain)</script></svg>
        """
      )

      on_exit(fn -> File.rm(path) end)

      upload = %Plug.Upload{
        path: path,
        filename: "payload.svg",
        content_type: "image/svg+xml"
      }

      params = %{
        "workspace_slug" => workspace.slug,
        "project_slug" => project.slug,
        "file" => upload
      }

      conn =
        conn
        |> Map.put(:params, params)
        |> assign(:current_scope, Scope.for_user(user))
        |> UploadController.create(params)

      assert %{"error" => "upload_failed"} = json_response(conn, 422)
      assert Assets.list_assets(project.id) == []
    end
  end
end
