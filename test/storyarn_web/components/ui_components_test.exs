defmodule StoryarnWeb.Components.UIComponentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.UIComponents

  # =============================================================================
  # role_badge/1
  # =============================================================================

  describe "role_badge/1" do
    test "renders owner badge with primary class" do
      html = render_component(&UIComponents.role_badge/1, %{role: "owner"})
      assert html =~ "badge-primary"
      assert html =~ "owner"
    end

    test "renders admin badge with secondary class" do
      html = render_component(&UIComponents.role_badge/1, %{role: "admin"})
      assert html =~ "badge-secondary"
      assert html =~ "admin"
    end

    test "renders editor badge with secondary class" do
      html = render_component(&UIComponents.role_badge/1, %{role: "editor"})
      assert html =~ "badge-secondary"
      assert html =~ "editor"
    end

    test "renders member badge with accent class" do
      html = render_component(&UIComponents.role_badge/1, %{role: "member"})
      assert html =~ "badge-accent"
      assert html =~ "member"
    end

    test "renders viewer badge with ghost class" do
      html = render_component(&UIComponents.role_badge/1, %{role: "viewer"})
      assert html =~ "badge-ghost"
      assert html =~ "viewer"
    end
  end

  # =============================================================================
  # oauth_buttons/1
  # =============================================================================

  describe "oauth_buttons/1" do
    test "renders login buttons by default" do
      html = render_component(&UIComponents.oauth_buttons/1, %{})
      assert html =~ ~s(href="/auth/github")
      assert html =~ ~s(href="/auth/google")
      assert html =~ ~s(href="/auth/discord")
      refute html =~ "/link"
    end

    test "renders link buttons when action is link" do
      html = render_component(&UIComponents.oauth_buttons/1, %{action: "link"})
      assert html =~ ~s(href="/auth/github/link")
      assert html =~ ~s(href="/auth/google/link")
      assert html =~ ~s(href="/auth/discord/link")
    end

    test "renders GitHub SVG icon" do
      html = render_component(&UIComponents.oauth_buttons/1, %{})
      assert html =~ "viewBox=\"0 0 24 24\""
      assert html =~ "Continue with GitHub"
    end

    test "renders Google SVG icon with colored paths" do
      html = render_component(&UIComponents.oauth_buttons/1, %{})
      assert html =~ "#4285F4"
      assert html =~ "Continue with Google"
    end

    test "renders Discord SVG icon" do
      html = render_component(&UIComponents.oauth_buttons/1, %{})
      assert html =~ "#5865F2"
      assert html =~ "Continue with Discord"
    end

    test "accepts custom class" do
      html = render_component(&UIComponents.oauth_buttons/1, %{class: "my-custom-class"})
      assert html =~ "my-custom-class"
    end
  end

  # =============================================================================
  # kbd/1
  # =============================================================================

  describe "kbd/1" do
    test "renders keyboard shortcut with default xs size" do
      html =
        render_component(&UIComponents.kbd/1, %{
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "E" end}]
        })

      assert html =~ "kbd-xs"
      assert html =~ "E"
    end

    test "renders keyboard shortcut with sm size" do
      html =
        render_component(&UIComponents.kbd/1, %{
          size: "sm",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Ctrl+S" end}]
        })

      assert html =~ "kbd-sm"
    end

    test "renders keyboard shortcut with md size" do
      html =
        render_component(&UIComponents.kbd/1, %{
          size: "md",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Enter" end}]
        })

      assert html =~ "kbd-md"
    end

    test "accepts custom class" do
      html =
        render_component(&UIComponents.kbd/1, %{
          class: "text-red",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "X" end}]
        })

      assert html =~ "text-red"
    end
  end

  # =============================================================================
  # empty_state/1
  # =============================================================================

  describe "empty_state/1" do
    test "renders icon and title" do
      html =
        render_component(&UIComponents.empty_state/1, %{
          icon: "folder-open",
          title: "No projects",
          inner_block: [],
          action: []
        })

      assert html =~ "folder-open"
      assert html =~ "No projects"
    end

    test "renders description from inner block" do
      html =
        render_component(&UIComponents.empty_state/1, %{
          icon: "file-text",
          title: nil,
          inner_block: [
            %{__slot__: :inner_block, inner_block: fn _, _ -> "Create your first document" end}
          ],
          action: []
        })

      assert html =~ "Create your first document"
    end

    test "renders action slot" do
      html =
        render_component(&UIComponents.empty_state/1, %{
          icon: "plus",
          title: "Empty",
          inner_block: [],
          action: [
            %{__slot__: :action, inner_block: fn _, _ -> "Add new" end}
          ]
        })

      assert html =~ "Add new"
    end

    test "hides title when nil" do
      html =
        render_component(&UIComponents.empty_state/1, %{
          icon: "box",
          title: nil,
          inner_block: [],
          action: []
        })

      refute html =~ "font-medium"
    end

    test "accepts custom class" do
      html =
        render_component(&UIComponents.empty_state/1, %{
          icon: "box",
          title: nil,
          class: "custom-class",
          inner_block: [],
          action: []
        })

      assert html =~ "custom-class"
    end
  end

  # =============================================================================
  # search_input/1
  # =============================================================================

  describe "search_input/1" do
    test "renders search input with default sm size" do
      html = render_component(&UIComponents.search_input/1, %{})
      assert html =~ "input-sm"
      assert html =~ "search"
      assert html =~ ~s(type="text")
    end

    test "renders with xs size" do
      html = render_component(&UIComponents.search_input/1, %{size: "xs"})
      assert html =~ "input-xs"
    end

    test "renders with lg size" do
      html = render_component(&UIComponents.search_input/1, %{size: "lg"})
      assert html =~ "input-lg"
    end

    test "passes through global attributes" do
      html =
        render_component(&UIComponents.search_input/1, %{
          placeholder: "Search here...",
          name: "q"
        })

      assert html =~ ~s(placeholder="Search here...")
      assert html =~ ~s(name="q")
    end

    test "accepts custom class" do
      html = render_component(&UIComponents.search_input/1, %{class: "w-full"})
      assert html =~ "w-full"
    end
  end

  # =============================================================================
  # avatar_group/1
  # =============================================================================

  describe "avatar_group/1" do
    test "renders avatars with images" do
      html =
        render_component(&UIComponents.avatar_group/1, %{
          avatar: [
            %{__slot__: :avatar, src: "/img/user1.jpg", alt: "User 1"},
            %{__slot__: :avatar, src: "/img/user2.jpg", alt: "User 2"}
          ]
        })

      assert html =~ ~s(src="/img/user1.jpg")
      assert html =~ ~s(src="/img/user2.jpg")
      assert html =~ "avatar-group"
    end

    test "renders fallback initials when no src" do
      html =
        render_component(&UIComponents.avatar_group/1, %{
          avatar: [
            %{__slot__: :avatar, fallback: "JD"}
          ]
        })

      assert html =~ "JD"
      assert html =~ "bg-neutral"
    end

    test "shows +N indicator when avatars exceed max" do
      html =
        render_component(&UIComponents.avatar_group/1, %{
          max: 2,
          avatar: [
            %{__slot__: :avatar, src: "/img/1.jpg"},
            %{__slot__: :avatar, src: "/img/2.jpg"},
            %{__slot__: :avatar, src: "/img/3.jpg"},
            %{__slot__: :avatar, src: "/img/4.jpg"}
          ]
        })

      assert html =~ "+2"
      assert html =~ "placeholder"
    end

    test "shows +N based on total when provided" do
      html =
        render_component(&UIComponents.avatar_group/1, %{
          max: 2,
          total: 10,
          avatar: [
            %{__slot__: :avatar, src: "/img/1.jpg"},
            %{__slot__: :avatar, src: "/img/2.jpg"}
          ]
        })

      assert html =~ "+8"
    end

    test "applies size class for sm" do
      html =
        render_component(&UIComponents.avatar_group/1, %{
          size: "sm",
          avatar: [%{__slot__: :avatar, src: "/img/1.jpg"}]
        })

      assert html =~ "w-8"
    end

    test "applies size class for lg" do
      html =
        render_component(&UIComponents.avatar_group/1, %{
          size: "lg",
          avatar: [%{__slot__: :avatar, src: "/img/1.jpg"}]
        })

      assert html =~ "w-12"
    end

    test "does not show +N when remaining is 0" do
      html =
        render_component(&UIComponents.avatar_group/1, %{
          max: 4,
          avatar: [
            %{__slot__: :avatar, src: "/img/1.jpg"},
            %{__slot__: :avatar, src: "/img/2.jpg"}
          ]
        })

      refute html =~ "placeholder"
    end
  end

  # =============================================================================
  # theme_toggle/1
  # =============================================================================

  describe "theme_toggle/1" do
    test "renders three theme buttons" do
      html = render_component(&UIComponents.theme_toggle/1, %{})

      assert html =~ ~s(data-phx-theme="system")
      assert html =~ ~s(data-phx-theme="light")
      assert html =~ ~s(data-phx-theme="dark")
    end

    test "renders monitor, sun, and moon icons" do
      html = render_component(&UIComponents.theme_toggle/1, %{})
      assert html =~ "monitor"
      assert html =~ "sun"
      assert html =~ "moon"
    end

    test "dispatches phx:set-theme event" do
      html = render_component(&UIComponents.theme_toggle/1, %{})
      assert html =~ "phx:set-theme"
    end
  end
end
