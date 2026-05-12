defmodule StoryarnWeb.Components.CoreComponentsTest do
  @moduledoc """
  Tests for CoreComponents — flash, icon, and JS commands.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.JS
  alias StoryarnWeb.Components.CoreComponents

  # =============================================================================
  # flash/1
  # =============================================================================

  describe "flash/1" do
    test "renders info flash with message from flash map" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{"info" => "Record saved successfully"}
        )

      assert html =~ "Record saved successfully"
      assert html =~ "bg-background"
      assert html =~ "role=\"alert\""
    end

    test "renders error flash with message from flash map" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Something went wrong"}
        )

      assert html =~ "Something went wrong"
      assert html =~ "bg-destructive"
    end

    test "renders nothing when no flash message for kind" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{}
        )

      refute html =~ "data-slot=\"toast\""
      refute html =~ "role=\"alert\""
    end

    test "renders nothing when flash has wrong kind" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{"error" => "Only error set"}
        )

      refute html =~ "Only error set"
    end

    test "renders with title" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{"info" => "Details here"},
          title: "Success!"
        )

      assert html =~ "Success!"
      assert html =~ "font-semibold"
      assert html =~ "Details here"
    end

    test "renders without title" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Oops"}
        )

      assert html =~ "Oops"
      refute html =~ "font-semibold"
    end

    test "uses custom id when provided" do
      html =
        render_component(&CoreComponents.flash/1,
          id: "my-custom-flash",
          kind: :info,
          flash: %{"info" => "Hi"}
        )

      assert html =~ ~s(id="my-custom-flash")
    end

    test "uses default id based on kind" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Err"}
        )

      assert html =~ ~s(id="flash-error")
    end

    test "info flash renders icon" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{"info" => "Message"}
        )

      assert html =~ "LucideIcon"
    end

    test "error flash renders icon" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Error message"}
        )

      assert html =~ "LucideIcon"
    end

    test "renders close button" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{"info" => "Closeable"}
        )

      assert html =~ "close"
      assert html =~ "button"
    end

    test "renders inner_block content instead of flash map message" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.flash kind={:info} flash={%{}}>
          Custom flash content
        </CoreComponents.flash>
        """)

      assert html =~ "Custom flash content"
      assert html =~ "bg-background"
    end
  end

  # =============================================================================
  # icon/1
  # =============================================================================

  describe "icon/1" do
    test "renders as Vue LucideIcon component" do
      html = render_component(&CoreComponents.icon/1, name: "x")
      vue = LiveVue.Test.get_vue(html)

      assert vue.component == "components/LucideIcon"
      assert vue.props["name"] == "x"
    end

    test "applies default size-4 class" do
      html = render_component(&CoreComponents.icon/1, name: "x")
      vue = LiveVue.Test.get_vue(html)

      assert vue.class =~ "size-4"
    end

    test "applies custom class" do
      html = render_component(&CoreComponents.icon/1, name: "x", class: "size-6 text-red-500")
      vue = LiveVue.Test.get_vue(html)

      assert vue.class =~ "size-6 text-red-500"
    end

    test "renders different icon names" do
      for name <- ["info", "alert-circle", "arrow-left", "lock", "x"] do
        html = render_component(&CoreComponents.icon/1, name: name)
        vue = LiveVue.Test.get_vue(html)

        assert vue.component == "components/LucideIcon"
        assert vue.props["name"] == name
      end
    end
  end

  # =============================================================================
  # JS Commands
  # =============================================================================

  describe "show/2" do
    test "returns JS struct" do
      result = CoreComponents.show("#my-element")
      assert %JS{} = result
    end

    test "accepts JS struct as first argument" do
      result = CoreComponents.show(%JS{}, "#my-element")
      assert %JS{} = result
    end
  end

  describe "hide/2" do
    test "returns JS struct" do
      result = CoreComponents.hide("#my-element")
      assert %JS{} = result
    end

    test "accepts JS struct as first argument" do
      result = CoreComponents.hide(%JS{}, "#my-element")
      assert %JS{} = result
    end
  end
end
