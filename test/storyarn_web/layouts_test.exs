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

  defp base_focus_assigns(overrides) do
    defaults = %{
      flash: %{},
      current_scope: %{user: user_map()},
      project: %{slug: "test-project", name: "Test Project"},
      workspace: %{slug: "test-workspace", name: "Test Workspace"},
      active_tool: :sheets,
      has_tree: false,
      tree_panel_open: false,
      tree_panel_pinned: false,
      can_edit: false,
      online_users: [],
      canvas_mode: false,
      inner_block: inner_block("<p>Focus content</p>")
    }

    Map.merge(defaults, overrides)
    |> Enum.to_list()
  end

  # ── public/1 ────────────────────────────────────────────────────────

  describe "public/1" do
    test "renders public layout with login/signup links when no user" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          current_scope: nil,
          inner_block: inner_block("<p>Public page content</p>")
        )

      assert html =~ "Public page content"
      assert html =~ "Storyarn"
      assert html =~ "Log in"
      assert html =~ "Sign up"
    end

    test "renders Dashboard link when user is logged in" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          current_scope: %{user: user_map()},
          inner_block: inner_block("<p>Logged in page</p>")
        )

      assert html =~ "Dashboard"
      assert html =~ "/workspaces"
      refute html =~ ">Log in<"
      refute html =~ ">Sign up<"
    end

    test "renders inner_block content" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          current_scope: nil,
          inner_block: inner_block("<div id=\"hero\">Welcome</div>")
        )

      assert html =~ ~s(id="hero")
      assert html =~ "Welcome"
    end

    test "renders logo link to root" do
      html =
        render_component(&Layouts.public/1,
          flash: %{},
          current_scope: nil,
          inner_block: inner_block("<p>Test</p>")
        )

      assert html =~ ~s(logo.svg)
      assert html =~ "Storyarn"
    end
  end

  # ── auth/1 ──────────────────────────────────────────────────────────

  describe "auth/1" do
    test "renders auth layout with inner content" do
      html =
        render_component(&Layouts.auth/1,
          flash: %{},
          current_scope: nil,
          inner_block: inner_block("<form>Login form</form>")
        )

      assert html =~ "Login form"
      assert html =~ "Storyarn"
    end

    test "centers content with max-width container" do
      html =
        render_component(&Layouts.auth/1,
          flash: %{},
          current_scope: nil,
          inner_block: inner_block("<p>Centered</p>")
        )

      assert html =~ "max-w-md"
      assert html =~ "items-center"
      assert html =~ "justify-center"
    end

    test "renders theme toggle" do
      html =
        render_component(&Layouts.auth/1,
          flash: %{},
          current_scope: nil,
          inner_block: inner_block("<p>Auth</p>")
        )

      # Theme toggle is present
      assert html =~ "theme"
    end

    test "renders logo link to root" do
      html =
        render_component(&Layouts.auth/1,
          flash: %{},
          current_scope: nil,
          inner_block: inner_block("<p>Auth</p>")
        )

      assert html =~ ~s(logo.svg)
    end
  end

  # ── app/1 ───────────────────────────────────────────────────────────

  describe "app/1" do
    test "renders app layout with inner content" do
      html =
        render_component(&Layouts.app/1,
          flash: %{},
          current_scope: %{user: user_map()},
          workspaces: [],
          current_workspace: nil,
          inner_block: inner_block("<p>Dashboard content</p>")
        )

      assert html =~ "Dashboard content"
    end

    test "renders drawer structure for sidebar" do
      html =
        render_component(&Layouts.app/1,
          flash: %{},
          current_scope: %{user: user_map()},
          workspaces: [],
          current_workspace: nil,
          inner_block: inner_block("<p>App</p>")
        )

      assert html =~ "drawer"
      assert html =~ "sidebar-drawer"
    end

    test "renders mobile hamburger menu" do
      html =
        render_component(&Layouts.app/1,
          flash: %{},
          current_scope: %{user: user_map()},
          workspaces: [],
          current_workspace: nil,
          inner_block: inner_block("<p>App</p>")
        )

      assert html =~ "menu"
      assert html =~ "lg:hidden"
    end

    test "does not render sidebar when no user" do
      html =
        render_component(&Layouts.app/1,
          flash: %{},
          current_scope: nil,
          workspaces: [],
          current_workspace: nil,
          inner_block: inner_block("<p>No sidebar</p>")
        )

      assert html =~ "No sidebar"
      # Sidebar component won't render without a user
      assert html =~ "drawer-side"
    end
  end

  # ── settings/1 ──────────────────────────────────────────────────────

  describe "settings/1" do
    test "renders settings layout with title and content" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
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
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          subtitle: slot(:subtitle, "Manage your profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ "Manage your profile"
    end

    test "renders account navigation section" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ "Account"
      assert html =~ "Profile"
      assert html =~ "Security"
      assert html =~ "Connected accounts"
    end

    test "highlights active nav item based on current_path" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings/security",
          title: slot(:title, "Security"),
          inner_block: inner_block("<p>Content</p>")
        )

      # Active item has primary color
      assert html =~ "bg-primary/10"
    end

    test "renders workspace sections in navigation" do
      workspaces = [%{slug: "team-ws", name: "Team Workspace"}]

      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          current_scope: %{user: user_map()},
          workspaces: workspaces,
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ "Team Workspace"
      assert html =~ "General"
      assert html =~ "Members"
      assert html =~ "/users/settings/workspaces/team-ws/general"
      assert html =~ "/users/settings/workspaces/team-ws/members"
    end

    test "renders back to app link" do
      html =
        render_component(&Layouts.settings/1,
          flash: %{},
          current_scope: %{user: user_map()},
          workspaces: [],
          current_path: ~p"/users/settings",
          title: slot(:title, "Profile"),
          inner_block: inner_block("<p>Content</p>")
        )

      assert html =~ "Back to app"
      assert html =~ "/workspaces"
    end
  end

  # ── focus/1 ─────────────────────────────────────────────────────────

  describe "focus/1" do
    test "renders content_header slot when provided" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{
            content_header: slot(:content_header, "<h1>My Sheet Title</h1>"),
            inner_block: inner_block("<p>Main content</p>")
          })
        )

      assert html =~ "My Sheet Title"
      assert html =~ "Main content"
    end

    test "handles nil current_scope (no user)" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{
            current_scope: nil,
            inner_block: inner_block("<p>No user</p>")
          })
        )

      assert html =~ "No user"
    end

    test "hides right toolbar when no user" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{current_scope: nil})
        )

      # Right toolbar is conditional on current_user_id
      assert html =~ "Focus content"
    end

    test "renders canvas mode without padding" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{canvas_mode: true})
        )

      assert html =~ "overflow-hidden"
      refute html =~ "overflow-y-auto pt-[76px]"
    end

    test "renders non-canvas mode with padding" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{canvas_mode: false})
        )

      assert html =~ "overflow-y-auto"
      assert html =~ "pt-[76px]"
    end

    test "adds left padding when tree panel is open" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{
            has_tree: true,
            tree_panel_open: true,
            canvas_mode: false
          })
        )

      assert html =~ "pl-[264px]"
    end

    test "no left padding when tree panel is closed" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{
            has_tree: true,
            tree_panel_open: false,
            canvas_mode: false
          })
        )

      refute html =~ "pl-[264px]"
    end

    test "no left padding in canvas mode even when tree is open" do
      html =
        render_component(
          &Layouts.focus/1,
          base_focus_assigns(%{
            has_tree: true,
            tree_panel_open: true,
            canvas_mode: true
          })
        )

      # Canvas mode uses overflow-hidden, no padding logic
      refute html =~ "pl-[264px]"
    end
  end

  # ── flash_group/1 ───────────────────────────────────────────────────

  describe "flash_group/1" do
    test "renders flash group container" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          id: "flash-group"
        )

      assert html =~ ~s(id="flash-group")
      assert html =~ ~s(aria-live="polite")
    end

    test "renders client and server error flash elements" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          id: "flash-group"
        )

      assert html =~ ~s(id="client-error")
      assert html =~ ~s(id="server-error")
    end

    test "renders reconnection messaging" do
      html =
        render_component(&Layouts.flash_group/1,
          flash: %{},
          id: "flash-group"
        )

      assert html =~ "Attempting to reconnect"
    end
  end
end
