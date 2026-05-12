defmodule StoryarnWeb.LayoutsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Layouts

  # ── Helpers ──────────────────────────────────────────────────────────

  defp slot(name, content) do
    [
      %{
        __slot__: name,
        inner_block: fn _assigns, _context -> {:safe, content} end
      }
    ]
  end

  defp inner_block(content), do: slot(:inner_block, content)

  defp user_map do
    %{id: 1, email: "t@t.com", display_name: "Test User"}
  end

  defp mock_socket do
    %Phoenix.LiveView.Socket{}
  end

  # ── public/1 ────────────────────────────────────────────────────────

  describe "public/1" do
    test "renders public LiveVue layout boundary when no user" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          inner_block: inner_block("<p>Public page content</p>")
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/public/Layout")

      assert vue.id == "public-layout"
      assert vue.props["is-logged-in"] == false
      assert vue.props["urls"]["login"] == "/users/log-in"
      assert html =~ "Public page content"
    end

    test "marks public layout as signed in when user is logged in" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: %{user: user_map()},
          inner_block: inner_block("<p>Logged in page</p>")
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/public/Layout")

      assert vue.props["is-logged-in"] == true
      assert vue.props["urls"]["workspaces"] == "/workspaces"
    end

    test "passes inner_block content through the public layout slot" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          inner_block: inner_block("<div id=\"hero\">Welcome</div>")
        )

      assert html =~ ~s(id="hero")
      assert html =~ "Welcome"
    end

    test "passes canonical public urls to Vue" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          inner_block: inner_block("<p>Test</p>")
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/public/Layout")

      assert vue.props["urls"] == %{
               "home" => "/",
               "docs" => "/docs",
               "contact" => "/contact",
               "login" => "/users/log-in",
               "workspaces" => "/workspaces"
             }
    end

    test "supports forcing a dark theme for the public subtree" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          theme: "dark",
          inner_block: inner_block("<p>Dark landing</p>")
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/public/Layout")

      assert vue.props["theme"] == "dark"
    end

    test "renders flash group outside public boundary" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          inner_block: inner_block("<p>Public page</p>")
        )

      assert html =~ ~s(id="flash-group")
    end
  end

  # ── auth/1 ──────────────────────────────────────────────────────────

  describe "auth/1" do
    test "renders auth layout with inner content" do
      html =
        render_component(&Layouts.auth/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          inner_block: inner_block("<form>Login form</form>")
        )

      assert html =~ "Login form"
      assert html =~ "live/layouts/auth/Layout"
    end

    test "renders auth LiveVue boundary" do
      html =
        render_component(&Layouts.auth/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          inner_block: inner_block("<p>Centered</p>")
        )

      assert html =~ ~s(id="auth-layout")
      assert html =~ ~s(data-name="live/layouts/auth/Layout")
    end

    test "renders flash group outside auth boundary" do
      html =
        render_component(&Layouts.auth/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: nil,
          inner_block: inner_block("<p>Auth</p>")
        )

      assert html =~ ~s(id="flash-group")
    end
  end

  # ── compare/1 ──────────────────────────────────────────────────────

  describe "compare/1" do
    test "renders compare LiveVue layout boundary and content" do
      html =
        render_component(&Layouts.compare/1,
          flash: %{},
          socket: mock_socket(),
          inner_block: inner_block("<p>Compare content</p>")
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/compare/Layout")

      assert vue.id == "compare-layout"
      assert vue.props["content-class"] == "h-full overflow-hidden"
      assert html =~ "Compare content"
    end

    test "passes panel and content options to compare layout" do
      html =
        render_component(&Layouts.compare/1,
          flash: %{},
          socket: mock_socket(),
          panel_title: "Layers",
          panel_open: false,
          content_class: "h-full overflow-y-auto p-4",
          inner_block: inner_block("<p>Scrollable compare</p>")
        )

      vue = LiveVue.Test.get_vue(html, name: "live/layouts/compare/Layout")

      assert vue.props["panel-title"] == "Layers"
      assert vue.props["panel-open"] == false
      assert vue.props["content-class"] == "h-full overflow-y-auto p-4"
    end

    test "renders flash group outside compare boundary" do
      html =
        render_component(&Layouts.compare/1,
          flash: %{},
          socket: mock_socket(),
          inner_block: inner_block("<p>Compare</p>")
        )

      assert html =~ ~s(id="flash-group")
    end
  end

  # ── settings/1 ──────────────────────────────────────────────────────

  describe "settings/1" do
    test "renders settings layout with title and content" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          inner_block: inner_block("<p>Profile settings</p>")
        )

      assert html =~ "Profile"
      assert html =~ "Profile settings"
    end

    test "renders subtitle slot when provided" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          subtitle: slot(:subtitle, "Manage your profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ "Manage your profile"
    end

    test "passes account settings context to LiveVue boundary" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ ~s(data-name="live/layouts/settings/Layout")
      assert html =~ "/users/settings"
      assert html =~ "managed-workspace-slugs"
      assert html =~ "workspaces"
    end

    test "passes workspace settings context to LiveVue boundary" do
      workspaces = [%{id: 1, slug: "team-ws", name: "Team Workspace"}]

      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: %{user: user_map()},
          workspaces: workspaces,
          managed_workspace_slugs: MapSet.new(["team-ws"]),
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ "Team Workspace"
      assert html =~ "team-ws"
      assert html =~ "managed-workspace-slugs"
    end

    test "renders settings LiveVue boundary and content" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          socket: mock_socket(),
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ ~s(id="settings-layout")
      assert html =~ "Content"
    end
  end

  # ── flash_group/1 ───────────────────────────────────────────────────

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
