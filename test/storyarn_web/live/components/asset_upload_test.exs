# Test LiveView that hosts the AssetUpload component
# Defined before the test module to avoid async compilation race conditions
defmodule AssetUploadTestLive do
  use Phoenix.LiveView

  def mount(_params, session, socket) do
    project = Storyarn.Projects.get_project!(session["project_id"])
    user = Storyarn.Accounts.get_user!(session["user_id"])

    {:ok,
     assign(socket,
       project: project,
       current_user: user,
       uploaded_asset: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={StoryarnWeb.Components.AssetUpload}
      id="test-upload"
      project={@project}
      current_user={@current_user}
      on_upload={fn asset -> send(self(), {:asset_uploaded, asset}) end}
    />
    """
  end

  def handle_info({:asset_uploaded, asset}, socket) do
    {:noreply, assign(socket, :uploaded_asset, asset)}
  end
end

defmodule AssetUploadTestLiveCustom do
  use Phoenix.LiveView

  def mount(_params, session, socket) do
    project = Storyarn.Projects.get_project!(session["project_id"])
    user = Storyarn.Accounts.get_user!(session["user_id"])

    {:ok,
     assign(socket,
       project: project,
       current_user: user
     )}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={StoryarnWeb.Components.AssetUpload}
      id="test-upload-custom"
      project={@project}
      current_user={@current_user}
      on_upload={fn _asset -> :ok end}
      accept={~w(audio/mpeg audio/wav)}
      max_entries={3}
      max_file_size={5 * 1024 * 1024}
    />
    """
  end
end

defmodule StoryarnWeb.Components.AssetUploadTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Storyarn.ProjectsFixtures

  # =============================================================================
  # LiveComponent rendering via test LiveView
  # =============================================================================

  describe "rendering" do
    setup :register_and_log_in_user

    test "renders upload area with all expected elements", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} =
        live_isolated(conn, AssetUploadTestLive,
          session: %{
            "project_id" => project.id,
            "user_id" => user.id
          }
        )

      html = render(view)

      assert html =~ "Browse Files"
      assert html =~ "Drag and drop"
      assert html =~ "Max file size"
      assert html =~ "10MB"
    end
  end

  describe "validate event" do
    setup :register_and_log_in_user

    test "validate event is handled without error", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} =
        live_isolated(conn, AssetUploadTestLive,
          session: %{
            "project_id" => project.id,
            "user_id" => user.id
          }
        )

      # Trigger validate event on the component
      html =
        view
        |> element("form")
        |> render_change(%{})

      assert html =~ "Browse Files"
    end
  end

  describe "update/2 with custom options" do
    setup :register_and_log_in_user

    test "renders with custom max file size", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} =
        live_isolated(conn, AssetUploadTestLiveCustom,
          session: %{
            "project_id" => project.id,
            "user_id" => user.id
          }
        )

      html = render(view)
      assert html =~ "5MB"
      refute html =~ "10MB"
    end
  end

  describe "file upload flow" do
    setup :register_and_log_in_user

    test "uploading a valid image shows filename", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} =
        live_isolated(conn, AssetUploadTestLive,
          session: %{
            "project_id" => project.id,
            "user_id" => user.id
          }
        )

      png_data = create_test_png()

      upload =
        file_input(view, "#test-upload-form", :asset, [
          %{
            name: "test_image.png",
            content: png_data,
            type: "image/png"
          }
        ])

      render_upload(upload, "test_image.png")

      html = render(view)
      assert html =~ "test_image.png"
    end

    test "submitting upload consumes the file and shows it as uploaded", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} =
        live_isolated(conn, AssetUploadTestLive,
          session: %{
            "project_id" => project.id,
            "user_id" => user.id
          }
        )

      png_data = create_test_png()

      upload =
        file_input(view, "#test-upload-form", :asset, [
          %{
            name: "uploaded.png",
            content: png_data,
            type: "image/png"
          }
        ])

      render_upload(upload, "uploaded.png")

      html =
        view
        |> element("form")
        |> render_submit(%{})

      # After submit, the file appears in the "Uploaded" section
      assert html =~ "Uploaded"
      assert html =~ "uploaded.png"
    end

    test "cancel_upload removes individual entry", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} =
        live_isolated(conn, AssetUploadTestLive,
          session: %{
            "project_id" => project.id,
            "user_id" => user.id
          }
        )

      png_data = create_test_png()

      upload =
        file_input(view, "#test-upload-form", :asset, [
          %{
            name: "cancel_me.png",
            content: png_data,
            type: "image/png"
          }
        ])

      render_upload(upload, "cancel_me.png")

      html = render(view)
      assert html =~ "cancel_me.png"

      view
      |> element("button[phx-click=\"cancel_upload\"]")
      |> render_click()

      html = render(view)
      refute html =~ "cancel_me.png"
      assert html =~ "Browse Files"
    end

    test "cancel_all removes all entries", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} =
        live_isolated(conn, AssetUploadTestLive,
          session: %{
            "project_id" => project.id,
            "user_id" => user.id
          }
        )

      png_data = create_test_png()

      upload =
        file_input(view, "#test-upload-form", :asset, [
          %{
            name: "remove_me.png",
            content: png_data,
            type: "image/png"
          }
        ])

      render_upload(upload, "remove_me.png")

      html = render(view)
      assert html =~ "remove_me.png"

      view
      |> element("button[phx-click=\"cancel_all\"]")
      |> render_click()

      html = render(view)
      refute html =~ "remove_me.png"
      assert html =~ "Browse Files"
    end
  end

  # Creates a minimal valid PNG file (1x1 pixel)
  defp create_test_png do
    <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2,
      0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 8, 215, 99, 248, 207, 192, 0, 0, 0,
      2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  end
end
