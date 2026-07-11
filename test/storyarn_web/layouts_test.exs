defmodule StoryarnWeb.LayoutsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Layouts

  # ── Helpers ──────────────────────────────────────────────────────────

  defp mock_socket do
    %Phoenix.LiveView.Socket{}
  end

  # ── flash_group/1 ───────────────────────────────────────────────────

  describe "root/1" do
    test "renders brand icon metadata for browsers and search surfaces", %{conn: conn} do
      html =
        rendered_to_string(
          Layouts.root(%{
            conn: conn,
            inner_content: ""
          })
        )

      assert html =~ ~s[href="/favicon.ico"]
      assert html =~ ~s[href="/images/logos/favicon-192.png"]
      assert html =~ ~s[sizes="192x192"]
      assert html =~ ~s[href="/images/logos/apple-touch-icon-180.png"]
      assert html =~ ~s[rel="apple-touch-icon"]
      assert html =~ ~s[href="/site.webmanifest"]
      assert html =~ ~s[name="theme-color"]
    end

    test "serves the web app manifest through static paths" do
      assert "site.webmanifest" in StoryarnWeb.static_paths()
      refute "uploads" in StoryarnWeb.static_paths()
    end
  end

  describe "flash_group/1" do
    test "renders flash group container" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          socket: mock_socket(),
          id: "flash-group"
        )

      assert html =~ ~s(id="flash-group")
      assert html =~ ~s(aria-live="polite")
    end

    test "passes current flash messages to Vue" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{
            "info" => "Saved",
            "warning" => "Check this",
            "error" => "Failed"
          },
          socket: mock_socket(),
          id: "flash-group"
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/flash/FlashGroup")

      assert vue.props["flash"]["info"] == "Saved"
      assert vue.props["flash"]["warning"] == "Check this"
      assert vue.props["flash"]["error"] == "Failed"
    end

    test "renders client and server error flash elements" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          socket: mock_socket(),
          id: "flash-group"
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/flash/FlashGroup")

      assert html =~ "#client-error"
      assert html =~ "#server-error"
      assert vue.props["network"]["clientTitle"] == "We can't find the internet"
      assert vue.props["network"]["serverTitle"] == "Something went wrong!"
    end

    test "renders reconnection messaging" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          socket: mock_socket(),
          id: "flash-group"
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/flash/FlashGroup")

      assert vue.props["network"]["reconnecting"] == "Attempting to reconnect"
    end
  end
end
