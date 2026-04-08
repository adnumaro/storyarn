defmodule StoryarnWeb.Components.CoreComponentsTest do
  @moduledoc """
  Tests for CoreComponents — flash, button, input, header, table, list, icon,
  block_label, back, modal, confirm_modal, JS commands, and error translators.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

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
  # button/1
  # =============================================================================

  describe "button/1" do
    test "renders as button element by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button>Click me</CoreComponents.button>
        """)

      assert html =~ "<button"
      assert html =~ "Click me"
      assert html =~ "btn"
    end

    test "renders as link when navigate is set" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button navigate="/dashboard">Go</CoreComponents.button>
        """)

      assert html =~ "/dashboard"
      assert html =~ "Go"
      assert html =~ "<a"
      refute html =~ "<button"
    end

    test "renders as link when href is set" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button href="https://example.com">External</CoreComponents.button>
        """)

      assert html =~ "https://example.com"
      assert html =~ "<a"
    end

    test "renders as link when patch is set" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button patch="/items?page=2">Next</CoreComponents.button>
        """)

      assert html =~ "/items?page=2"
      assert html =~ "<a"
    end

    test "renders primary variant" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button variant="primary">Save</CoreComponents.button>
        """)

      assert html =~ "btn-primary"
      refute html =~ "btn-soft"
    end

    test "renders error variant" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button variant="error">Delete</CoreComponents.button>
        """)

      assert html =~ "btn-error"
      refute html =~ "btn-primary"
    end

    test "renders default variant (nil) with soft primary" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button>Default</CoreComponents.button>
        """)

      assert html =~ "btn-primary"
      assert html =~ "btn-soft"
    end

    test "passes global attributes through" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button disabled>Disabled</CoreComponents.button>
        """)

      assert html =~ "disabled"
    end

    test "accepts custom class" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button class="my-custom-class">Styled</CoreComponents.button>
        """)

      assert html =~ "my-custom-class"
    end

    test "renders phx-click attribute" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.button phx-click="do_something">Action</CoreComponents.button>
        """)

      assert html =~ "phx-click"
      assert html =~ "do_something"
    end
  end

  # =============================================================================
  # table/1
  # =============================================================================

  describe "table/1" do
    test "renders table with column labels and rows" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table id="users" rows={[%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]}>
          <:col :let={user} label="Name">{user.name}</:col>
        </CoreComponents.table>
        """)

      assert html =~ "<table"
      assert html =~ "Name"
      assert html =~ "Alice"
      assert html =~ "Bob"
    end

    test "renders table with multiple columns" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table id="items" rows={[%{id: 1, name: "Widget", price: 10}]}>
          <:col :let={item} label="Name">{item.name}</:col>
          <:col :let={item} label="Price">{item.price}</:col>
        </CoreComponents.table>
        """)

      assert html =~ "Name"
      assert html =~ "Price"
      assert html =~ "Widget"
      assert html =~ "10"
    end

    test "renders table with action column" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table id="items" rows={[%{id: 1, name: "Item"}]}>
          <:col :let={item} label="Name">{item.name}</:col>
          <:action :let={_item}>
            <button>Edit</button>
          </:action>
        </CoreComponents.table>
        """)

      assert html =~ "Edit"
      assert html =~ "sr-only"
    end

    test "renders table without action header when no actions" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table id="items" rows={[%{id: 1, name: "Item"}]}>
          <:col :let={item} label="Name">{item.name}</:col>
        </CoreComponents.table>
        """)

      refute html =~ "sr-only"
    end

    test "renders with row_id function" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table
          id="items"
          rows={[%{id: 42, name: "Widget"}]}
          row_id={fn row -> "row-#{row.id}" end}
        >
          <:col :let={item} label="Name">{item.name}</:col>
        </CoreComponents.table>
        """)

      assert html =~ ~s(id="row-42")
    end

    test "renders with row_click" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table
          id="items"
          rows={[%{id: 1, name: "Widget"}]}
          row_click={fn row -> JS.navigate("/items/#{row.id}") end}
        >
          <:col :let={item} label="Name">{item.name}</:col>
        </CoreComponents.table>
        """)

      assert html =~ "hover:cursor-pointer"
      assert html =~ "phx-click"
    end

    test "renders tbody with id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table id="my-table" rows={[]}>
          <:col label="Col"></:col>
        </CoreComponents.table>
        """)

      assert html =~ ~s(id="my-table")
    end

    test "renders empty table with no rows" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.table id="empty" rows={[]}>
          <:col label="Name"></:col>
        </CoreComponents.table>
        """)

      assert html =~ "<table"
      assert html =~ "Name"
    end
  end

  # =============================================================================
  # list/1
  # =============================================================================

  describe "list/1" do
    test "renders data list with item titles and values" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.list>
          <:item title="Name">Alice</:item>
          <:item title="Email">alice@example.com</:item>
        </CoreComponents.list>
        """)

      assert html =~ "<ul"
      assert html =~ "Name"
      assert html =~ "Alice"
      assert html =~ "Email"
      assert html =~ "alice@example.com"
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
  # back/1
  # =============================================================================

  describe "back/1" do
    test "renders back link with navigate" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.back navigate="/posts">Back to posts</CoreComponents.back>
        """)

      assert html =~ "/posts"
      assert html =~ "Back to posts"
      assert html =~ "svg"
    end

    test "renders with arrow icon" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.back navigate="/">Home</CoreComponents.back>
        """)

      assert html =~ "svg"
    end

    test "renders as a link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.back navigate="/items">Go back</CoreComponents.back>
        """)

      assert html =~ "<a"
      assert html =~ "/items"
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

  # =============================================================================
  # translate_error/1
  # =============================================================================

  describe "translate_error/1" do
    test "translates simple error message" do
      result = CoreComponents.translate_error({"can't be blank", []})
      assert is_binary(result)
      assert result =~ "can't be blank"
    end

    test "translates error with interpolation" do
      result =
        CoreComponents.translate_error(
          {"should be at least %{count} character(s)",
           [count: 3, validation: :length, kind: :min]}
        )

      assert is_binary(result)
      assert result =~ "3"
    end

    test "translates error with count (plural)" do
      result =
        CoreComponents.translate_error({"should have %{count} item(s)", [count: 5]})

      assert is_binary(result)
      assert result =~ "5"
    end

    test "translates error without opts" do
      result = CoreComponents.translate_error({"is invalid", []})
      assert result =~ "is invalid"
    end
  end

  # =============================================================================
  # translate_errors/2
  # =============================================================================

  describe "translate_errors/2" do
    test "translates errors for a matching field" do
      errors = [
        name: {"can't be blank", []},
        name: {"is too short", [count: 3]},
        email: {"is invalid", []}
      ]

      result = CoreComponents.translate_errors(errors, :name)
      assert length(result) == 2
      assert Enum.all?(result, &is_binary/1)
    end

    test "returns empty list for non-matching field" do
      errors = [name: {"can't be blank", []}]
      result = CoreComponents.translate_errors(errors, :email)
      assert result == []
    end

    test "returns empty list for empty errors" do
      result = CoreComponents.translate_errors([], :name)
      assert result == []
    end

    test "handles multiple fields correctly" do
      errors = [
        name: {"required", []},
        email: {"is invalid", []},
        email: {"already taken", []}
      ]

      name_errors = CoreComponents.translate_errors(errors, :name)
      email_errors = CoreComponents.translate_errors(errors, :email)

      assert length(name_errors) == 1
      assert length(email_errors) == 2
    end
  end
end
