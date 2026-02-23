defmodule StoryarnWeb.Components.AudioPickerTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias StoryarnWeb.Components.AudioPicker

  # A minimal LiveView host for testing the AudioPicker LiveComponent.
  # Uses live_isolated/3 so no route is needed.
  defmodule TestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <.live_component
        module={AudioPicker}
        id="test-audio-picker"
        project={@project}
        current_user={@current_user}
        selected_asset_id={@selected_asset_id}
        can_edit={@can_edit}
      />
      <div :if={@last_event} id="last-event">{inspect(@last_event)}</div>
      <div :if={@last_error} id="last-error">{@last_error}</div>
      """
    end

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         project: session["project"],
         current_user: session["current_user"],
         selected_asset_id: session["selected_asset_id"],
         can_edit: session["can_edit"],
         last_event: nil,
         last_error: nil
       )}
    end

    def handle_info({:audio_picker, :selected, asset_id}, socket) do
      {:noreply, assign(socket, last_event: {:selected, asset_id}, selected_asset_id: asset_id)}
    end

    def handle_info({:audio_picker, :error, message}, socket) do
      {:noreply, Phoenix.Component.assign(socket, :last_error, message)}
    end
  end

  defp mount_picker(conn, project, user, opts \\ []) do
    live_isolated(conn, TestLive,
      session: %{
        "project" => project,
        "current_user" => user,
        "selected_asset_id" => Keyword.get(opts, :selected_asset_id),
        "can_edit" => Keyword.get(opts, :can_edit, true)
      }
    )
  end

  describe "select and preview" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user)
      %{project: project}
    end

    test "renders with no selection and shows help text", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, _view, html} = mount_picker(conn, project, user)

      assert html =~ "No audio"
      assert html =~ "Attach voice-over or ambient audio."
      refute html =~ "<audio"
    end

    test "renders with pre-selected audio showing preview", %{
      conn: conn,
      project: project,
      user: user
    } do
      audio = audio_asset_fixture(project, user, %{filename: "greeting.mp3"})

      {:ok, _view, html} =
        mount_picker(conn, project, user, selected_asset_id: audio.id)

      assert html =~ "greeting.mp3"
      assert html =~ "<audio"
      assert html =~ "Remove"
    end

    test "lists only audio assets, not images", %{
      conn: conn,
      project: project,
      user: user
    } do
      _image = image_asset_fixture(project, user, %{filename: "picture.png"})
      _audio = audio_asset_fixture(project, user, %{filename: "voice_line.mp3"})

      {:ok, _view, html} = mount_picker(conn, project, user)

      assert html =~ "voice_line.mp3"
      refute html =~ "picture.png"
    end

    test "selecting audio sends event to parent", %{
      conn: conn,
      project: project,
      user: user
    } do
      audio = audio_asset_fixture(project, user, %{filename: "selected.mp3"})

      {:ok, view, _html} = mount_picker(conn, project, user)

      view
      |> element("form")
      |> render_change(%{"audio_asset_id" => to_string(audio.id)})

      html = render(view)
      assert html =~ "{:selected, #{audio.id}}"
      assert html =~ "selected.mp3"
      assert html =~ "<audio"
    end

    test "selecting 'No audio' sends nil event", %{
      conn: conn,
      project: project,
      user: user
    } do
      audio = audio_asset_fixture(project, user)

      {:ok, view, _html} =
        mount_picker(conn, project, user, selected_asset_id: audio.id)

      view
      |> element("form")
      |> render_change(%{"audio_asset_id" => ""})

      html = render(view)
      assert html =~ "{:selected, nil}"
      refute html =~ "<audio"
    end

    test "remove button unlinks audio and sends nil", %{
      conn: conn,
      project: project,
      user: user
    } do
      audio = audio_asset_fixture(project, user, %{filename: "removable.mp3"})

      {:ok, view, _html} =
        mount_picker(conn, project, user, selected_asset_id: audio.id)

      view
      |> element("button", "Remove")
      |> render_click()

      html = render(view)
      assert html =~ "{:selected, nil}"
      refute html =~ "<audio"
      refute html =~ "Preview:"
    end

    test "read-only mode hides select, upload, and remove button", %{
      conn: conn,
      project: project,
      user: user
    } do
      audio = audio_asset_fixture(project, user, %{filename: "readonly.mp3"})

      {:ok, _view, html} =
        mount_picker(conn, project, user,
          selected_asset_id: audio.id,
          can_edit: false
        )

      assert html =~ "readonly.mp3"
      assert html =~ "<audio"
      refute html =~ "<select"
      refute html =~ "Remove"
      refute html =~ "Upload audio"
    end

    test "read-only mode with no selection renders nothing visible", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, _view, html} =
        mount_picker(conn, project, user, can_edit: false)

      refute html =~ "<select"
      refute html =~ "<audio"
      refute html =~ "Attach voice-over"
      refute html =~ "Upload audio"
    end
  end

  describe "upload" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user)
      %{project: project}
    end

    test "renders upload button in edit mode", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, _view, html} = mount_picker(conn, project, user)
      assert html =~ "Upload audio"
    end

    test "upload_audio creates asset and auto-selects", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, view, _html} = mount_picker(conn, project, user)

      # Simulate the JS hook pushing the upload_audio event
      binary_data = "fake audio binary content"
      base64 = Base.encode64(binary_data)
      data_url = "data:audio/mpeg;base64,#{base64}"

      view
      |> element("#test-audio-picker-audio-input")
      |> render_hook("upload_audio", %{
        "filename" => "voice_line.mp3",
        "content_type" => "audio/mpeg",
        "data" => data_url
      })

      html = render(view)

      # Asset was auto-selected and event sent to parent
      assert html =~ "voice_line.mp3"
      assert html =~ "<audio"
      assert html =~ "last-event"

      # Asset was created in DB
      assets = Assets.list_assets(project.id, content_type: "audio/")
      assert length(assets) == 1
      assert hd(assets).filename == "voice_line.mp3"
      assert hd(assets).content_type == "audio/mpeg"
      assert hd(assets).size == byte_size(binary_data)
    end

    test "upload_audio adds new asset to existing dropdown list", %{
      conn: conn,
      project: project,
      user: user
    } do
      _existing = audio_asset_fixture(project, user, %{filename: "existing.mp3"})
      {:ok, view, html} = mount_picker(conn, project, user)
      assert html =~ "existing.mp3"

      binary_data = "new audio"
      base64 = Base.encode64(binary_data)

      view
      |> element("#test-audio-picker-audio-input")
      |> render_hook("upload_audio", %{
        "filename" => "new_upload.mp3",
        "content_type" => "audio/mpeg",
        "data" => "data:audio/mpeg;base64,#{base64}"
      })

      html = render(view)
      # Both old and new assets in dropdown
      assert html =~ "existing.mp3"
      assert html =~ "new_upload.mp3"
    end

    test "upload_validation_error sends error to parent", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, view, _html} = mount_picker(conn, project, user)

      view
      |> element("#test-audio-picker-audio-input")
      |> render_hook("upload_validation_error", %{
        "message" => "Please select an audio file."
      })

      html = render(view)
      assert html =~ "Please select an audio file."
    end

    test "upload_started shows loading state", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, view, _html} = mount_picker(conn, project, user)

      view
      |> element("#test-audio-picker-audio-input")
      |> render_hook("upload_started", %{})

      html = render(view)
      assert html =~ "Uploading..."
      assert html =~ "loading-spinner"
    end

    test "invalid base64 sends error", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, view, _html} = mount_picker(conn, project, user)

      view
      |> element("#test-audio-picker-audio-input")
      |> render_hook("upload_audio", %{
        "filename" => "bad.mp3",
        "content_type" => "audio/mpeg",
        "data" => "data:audio/mpeg;base64,!!!invalid!!!"
      })

      html = render(view)
      assert html =~ "Invalid file data."
    end
  end
end
