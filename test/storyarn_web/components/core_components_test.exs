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
      assert html =~ "alert-info"
      assert html =~ "role=\"alert\""
    end

    test "renders error flash with message from flash map" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Something went wrong"}
        )

      assert html =~ "Something went wrong"
      assert html =~ "alert-error"
    end

    test "renders nothing when no flash message for kind" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{}
        )

      refute html =~ "alert"
      refute html =~ "role=\"alert\""
    end

    test "renders nothing when flash has wrong kind" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :info,
          flash: %{"error" => "Only error set"}
        )

      refute html =~ "Only error set"
      refute html =~ "alert-info"
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

      assert html =~ "svg"
    end

    test "error flash renders icon" do
      html =
        render_component(&CoreComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Error message"}
        )

      assert html =~ "svg"
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
      assert html =~ "alert-info"
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
  # input/1
  # =============================================================================

  describe "input/1 — text (default)" do
    test "renders text input with name and value" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "user[name]",
          value: "John",
          id: "user_name",
          errors: []
        )

      assert html =~ ~s(type="text")
      assert html =~ ~s(name="user[name]")
      assert html =~ ~s(value="John")
      assert html =~ ~s(id="user_name")
    end

    test "renders label when provided" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "user[email]",
          value: "",
          id: "user_email",
          label: "Email Address",
          errors: []
        )

      assert html =~ "Email Address"
      assert html =~ "label"
    end

    test "renders without label span when nil" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "user[email]",
          value: "",
          id: "user_email",
          errors: []
        )

      # The <span class="label mb-1"> should not be present
      refute html =~ "label mb-1"
    end

    test "renders error messages" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "user[name]",
          value: "",
          id: "user_name",
          errors: ["can't be blank"]
        )

      assert html =~ "can&#39;t be blank"
      assert html =~ "text-error"
      assert html =~ "input-error"
    end

    test "renders email type" do
      html =
        render_component(&CoreComponents.input/1,
          type: "email",
          name: "user[email]",
          value: "test@example.com",
          id: "user_email",
          errors: []
        )

      assert html =~ ~s(type="email")
    end

    test "renders password type" do
      html =
        render_component(&CoreComponents.input/1,
          type: "password",
          name: "user[password]",
          value: "",
          id: "user_password",
          errors: []
        )

      assert html =~ ~s(type="password")
    end

    test "renders number type" do
      html =
        render_component(&CoreComponents.input/1,
          type: "number",
          name: "item[quantity]",
          value: "5",
          id: "item_quantity",
          errors: []
        )

      assert html =~ ~s(type="number")
    end

    test "renders with placeholder" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "search",
          value: "",
          id: "search",
          placeholder: "Search...",
          errors: []
        )

      assert html =~ ~s(placeholder="Search...")
    end

    test "applies custom class" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "field",
          value: "",
          id: "field",
          class: "custom-input-class",
          errors: []
        )

      assert html =~ "custom-input-class"
    end

    test "applies custom error_class" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "field",
          value: "",
          id: "field",
          error_class: "my-error",
          errors: ["required"]
        )

      assert html =~ "my-error"
    end

    test "applies default input class when no custom class" do
      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          name: "field",
          value: "",
          id: "field",
          errors: []
        )

      assert html =~ "w-full input"
    end
  end

  describe "input/1 — checkbox" do
    test "renders checkbox input" do
      html =
        render_component(&CoreComponents.input/1,
          type: "checkbox",
          name: "user[admin]",
          value: "true",
          id: "user_admin",
          label: "Is Admin",
          errors: []
        )

      assert html =~ ~s(type="checkbox")
      assert html =~ ~s(value="true")
      assert html =~ "Is Admin"
    end

    test "renders hidden input for false value" do
      html =
        render_component(&CoreComponents.input/1,
          type: "checkbox",
          name: "user[admin]",
          value: "false",
          id: "user_admin",
          errors: []
        )

      assert html =~ ~s(type="hidden")
      assert html =~ ~s(value="false")
    end

    test "renders checked checkbox" do
      html =
        render_component(&CoreComponents.input/1,
          type: "checkbox",
          name: "user[terms]",
          value: "true",
          checked: true,
          id: "user_terms",
          errors: []
        )

      assert html =~ "checked"
    end

    test "renders checkbox errors" do
      html =
        render_component(&CoreComponents.input/1,
          type: "checkbox",
          name: "user[terms]",
          value: "false",
          id: "user_terms",
          errors: ["must be accepted"]
        )

      assert html =~ "must be accepted"
      assert html =~ "text-error"
    end

    test "applies custom class to checkbox" do
      html =
        render_component(&CoreComponents.input/1,
          type: "checkbox",
          name: "field",
          value: "true",
          id: "field",
          class: "custom-checkbox",
          errors: []
        )

      assert html =~ "custom-checkbox"
    end

    test "applies default checkbox class" do
      html =
        render_component(&CoreComponents.input/1,
          type: "checkbox",
          name: "field",
          value: "true",
          id: "field",
          errors: []
        )

      assert html =~ "checkbox checkbox-sm"
    end
  end

  describe "input/1 — select" do
    test "renders select with options" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "user[role]",
          value: "admin",
          id: "user_role",
          options: [{"Admin", "admin"}, {"User", "user"}],
          errors: []
        )

      assert html =~ "<select"
      assert html =~ "Admin"
      assert html =~ "User"
    end

    test "renders select with prompt" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "user[role]",
          value: nil,
          id: "user_role",
          options: [{"Admin", "admin"}],
          prompt: "Choose a role...",
          errors: []
        )

      assert html =~ "Choose a role..."
    end

    test "renders select without prompt" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "user[role]",
          value: nil,
          id: "user_role",
          options: [{"Admin", "admin"}],
          errors: []
        )

      refute html =~ "Choose"
    end

    test "renders select with label" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "user[role]",
          value: nil,
          id: "user_role",
          options: [{"Admin", "admin"}],
          label: "User Role",
          errors: []
        )

      assert html =~ "User Role"
    end

    test "renders select errors" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "user[role]",
          value: nil,
          id: "user_role",
          options: [{"Admin", "admin"}],
          errors: ["is required"]
        )

      assert html =~ "is required"
      assert html =~ "select-error"
    end

    test "renders multiple select" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "user[roles]",
          value: [],
          id: "user_roles",
          options: [{"Admin", "admin"}, {"User", "user"}],
          multiple: true,
          errors: []
        )

      assert html =~ "multiple"
    end

    test "applies custom class to select" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "field",
          value: nil,
          id: "field",
          options: [],
          class: "custom-select",
          errors: []
        )

      assert html =~ "custom-select"
    end

    test "applies custom error_class to select" do
      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          name: "field",
          value: nil,
          id: "field",
          options: [],
          error_class: "my-sel-error",
          errors: ["bad"]
        )

      assert html =~ "my-sel-error"
    end
  end

  describe "input/1 — textarea" do
    test "renders textarea with name and value" do
      html =
        render_component(&CoreComponents.input/1,
          type: "textarea",
          name: "post[body]",
          value: "Hello world",
          id: "post_body",
          errors: []
        )

      assert html =~ "<textarea"
      assert html =~ "Hello world"
      assert html =~ ~s(name="post[body]")
    end

    test "renders textarea with label" do
      html =
        render_component(&CoreComponents.input/1,
          type: "textarea",
          name: "post[body]",
          value: "",
          id: "post_body",
          label: "Post Body",
          errors: []
        )

      assert html =~ "Post Body"
    end

    test "renders textarea errors" do
      html =
        render_component(&CoreComponents.input/1,
          type: "textarea",
          name: "post[body]",
          value: "",
          id: "post_body",
          errors: ["is too short"]
        )

      assert html =~ "is too short"
      assert html =~ "textarea-error"
    end

    test "applies custom class to textarea" do
      html =
        render_component(&CoreComponents.input/1,
          type: "textarea",
          name: "field",
          value: "",
          id: "field",
          class: "my-textarea",
          errors: []
        )

      assert html =~ "my-textarea"
    end

    test "applies custom error_class to textarea" do
      html =
        render_component(&CoreComponents.input/1,
          type: "textarea",
          name: "field",
          value: "",
          id: "field",
          error_class: "ta-error",
          errors: ["bad"]
        )

      assert html =~ "ta-error"
    end

    test "renders textarea with rows attribute" do
      html =
        render_component(&CoreComponents.input/1,
          type: "textarea",
          name: "field",
          value: "",
          id: "field",
          rows: "5",
          errors: []
        )

      assert html =~ ~s(rows="5")
    end
  end

  describe "input/1 — with FormField" do
    test "extracts name and id from form field" do
      form = Phoenix.Component.to_form(%{"email" => "test@example.com"}, as: "user")
      field = form[:email]

      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          field: field,
          errors: []
        )

      assert html =~ ~s(name="user[email]")
      assert html =~ ~s(id="user_email")
      assert html =~ ~s(value="test@example.com")
    end

    test "uses provided id over field id" do
      form = Phoenix.Component.to_form(%{"name" => ""}, as: "user")
      field = form[:name]

      html =
        render_component(&CoreComponents.input/1,
          type: "text",
          field: field,
          id: "custom-id",
          errors: []
        )

      assert html =~ ~s(id="custom-id")
    end

    test "extracts checkbox value from form field" do
      form = Phoenix.Component.to_form(%{"active" => "true"}, as: "user")
      field = form[:active]

      html =
        render_component(&CoreComponents.input/1,
          type: "checkbox",
          field: field,
          errors: []
        )

      assert html =~ ~s(type="checkbox")
      assert html =~ ~s(name="user[active]")
    end

    test "handles multiple select with form field" do
      form = Phoenix.Component.to_form(%{"tags" => []}, as: "post")
      field = form[:tags]

      html =
        render_component(&CoreComponents.input/1,
          type: "select",
          field: field,
          options: [{"Tag A", "a"}, {"Tag B", "b"}],
          multiple: true,
          errors: []
        )

      assert html =~ ~s(name="post[tags][]")
      assert html =~ "multiple"
    end
  end

  # =============================================================================
  # header/1
  # =============================================================================

  describe "header/1" do
    test "renders title in h1" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.header>
          My Page Title
        </CoreComponents.header>
        """)

      assert html =~ "<h1"
      assert html =~ "My Page Title"
    end

    test "renders with subtitle" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.header>
          Title
          <:subtitle>A helpful subtitle</:subtitle>
        </CoreComponents.header>
        """)

      assert html =~ "Title"
      assert html =~ "A helpful subtitle"
      assert html =~ "text-base-content/70"
    end

    test "renders without subtitle paragraph when no subtitle slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.header>
          Title Only
        </CoreComponents.header>
        """)

      assert html =~ "Title Only"
      refute html =~ "text-base-content/70"
    end

    test "renders with actions" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.header>
          Title
          <:actions>
            <button>New Item</button>
          </:actions>
        </CoreComponents.header>
        """)

      assert html =~ "New Item"
      assert html =~ "flex items-center justify-between"
    end

    test "does not add flex justify-between when no actions" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.header>
          No Actions
        </CoreComponents.header>
        """)

      refute html =~ "justify-between"
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
    test "renders lucide icon as svg" do
      html = render_component(&CoreComponents.icon/1, name: "x")
      assert html =~ "svg"
    end

    test "applies default size-4 class" do
      html = render_component(&CoreComponents.icon/1, name: "x")
      assert html =~ "size-4"
    end

    test "applies custom class" do
      html = render_component(&CoreComponents.icon/1, name: "x", class: "size-6 text-red-500")
      assert html =~ "size-6"
      assert html =~ "text-red-500"
    end

    test "renders different icon names" do
      for name <- ["info", "alert-circle", "arrow-left", "lock", "x"] do
        html = render_component(&CoreComponents.icon/1, name: name)
        assert html =~ "svg", "Expected SVG for icon: #{name}"
      end
    end

    test "applies style attribute" do
      html = render_component(&CoreComponents.icon/1, name: "x", style: "color: red")
      assert html =~ "color: red"
    end
  end

  # =============================================================================
  # block_label/1
  # =============================================================================

  describe "block_label/1" do
    test "renders label text" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "Health Points"
        )

      assert html =~ "Health Points"
      assert html =~ "<label"
    end

    test "hides when label is empty string" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: ""
        )

      refute html =~ "<label"
    end

    test "shows lock icon for constants" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "Max HP",
          is_constant: true
        )

      assert html =~ "Max HP"
      assert html =~ "text-error"
      assert html =~ "svg"
    end

    test "does not show lock icon for non-constants" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "Health",
          is_constant: false
        )

      assert html =~ "Health"
      refute html =~ "text-error"
    end

    test "shows editable span when can_edit and block_id are set" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "Editable Label",
          can_edit: true,
          block_id: 42
        )

      assert html =~ "Editable Label"
      assert html =~ "EditableBlockLabel"
      assert html =~ ~s(id="block-label-42")
      assert html =~ ~s(data-label="Editable Label")
      assert html =~ ~s(data-block-id="42")
      assert html =~ "cursor-default"
    end

    test "shows plain span when can_edit is false" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "Read Only",
          can_edit: false,
          block_id: 42
        )

      assert html =~ "Read Only"
      refute html =~ "EditableBlockLabel"
      refute html =~ "cursor-default"
    end

    test "shows plain span when block_id is nil" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "No Block",
          can_edit: true,
          block_id: nil
        )

      assert html =~ "No Block"
      refute html =~ "EditableBlockLabel"
    end

    test "shows both constant icon and editable span" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "Constant Editable",
          is_constant: true,
          can_edit: true,
          block_id: 99
        )

      assert html =~ "text-error"
      assert html =~ "EditableBlockLabel"
      assert html =~ "Constant Editable"
    end

    test "passes target to data attribute" do
      html =
        render_component(&CoreComponents.block_label/1,
          label: "With Target",
          can_edit: true,
          block_id: 1,
          target: "#my-component"
        )

      assert html =~ "data-phx-target"
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
  # modal/1
  # =============================================================================

  describe "modal/1" do
    test "renders dialog element with id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.modal id="test-modal">
          Modal content here
        </CoreComponents.modal>
        """)

      assert html =~ "<dialog"
      assert html =~ ~s(id="test-modal")
      assert html =~ "Modal content here"
      assert html =~ "modal"
    end

    test "renders close button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.modal id="close-modal">
          Content
        </CoreComponents.modal>
        """)

      assert html =~ "close"
      assert html =~ "btn-circle"
    end

    test "renders modal-box container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.modal id="box-modal">
          Content
        </CoreComponents.modal>
        """)

      assert html =~ "modal-box"
      assert html =~ ~s(id="box-modal-container")
    end

    test "renders modal backdrop" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.modal id="backdrop-modal">
          Content
        </CoreComponents.modal>
        """)

      assert html =~ "modal-backdrop"
    end

    test "renders phx-remove for hide_modal" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.modal id="removable-modal">
          Content
        </CoreComponents.modal>
        """)

      assert html =~ "phx-remove"
    end

    test "renders escape key handler" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.modal id="esc-modal">
          Content
        </CoreComponents.modal>
        """)

      assert html =~ "phx-key=\"escape\""
      assert html =~ "phx-window-keydown"
    end

    test "renders phx-click-away" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.modal id="clickaway-modal">
          Content
        </CoreComponents.modal>
        """)

      assert html =~ "phx-click-away"
    end
  end

  # =============================================================================
  # confirm_modal/1
  # =============================================================================

  describe "confirm_modal/1" do
    test "renders confirmation dialog with title" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "delete-confirm",
          title: "Delete item?",
          on_confirm: JS.push("delete")
        )

      assert html =~ "<dialog"
      assert html =~ "Delete item?"
      assert html =~ ~s(id="delete-confirm")
    end

    test "renders with message" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-1",
          title: "Confirm?",
          message: "This action cannot be undone.",
          on_confirm: JS.push("confirm")
        )

      assert html =~ "This action cannot be undone."
    end

    test "renders without message when nil" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-2",
          title: "Confirm?",
          on_confirm: JS.push("confirm")
        )

      refute html =~ "text-base-content/70 mb-6"
    end

    test "renders default confirm and cancel text" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-3",
          title: "Sure?",
          on_confirm: JS.push("do_it")
        )

      assert html =~ "Confirm"
      assert html =~ "Cancel"
    end

    test "renders custom confirm and cancel text" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-4",
          title: "Delete?",
          confirm_text: "Yes, delete",
          cancel_text: "No, keep it",
          on_confirm: JS.push("delete")
        )

      assert html =~ "Yes, delete"
      assert html =~ "No, keep it"
    end

    test "renders primary variant (default)" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-primary",
          title: "Confirm?",
          confirm_variant: "primary",
          on_confirm: JS.push("confirm")
        )

      assert html =~ "btn-primary"
      refute html =~ "btn-error"
      refute html =~ "btn-warning"
    end

    test "renders error variant" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-error",
          title: "Delete?",
          confirm_variant: "error",
          on_confirm: JS.push("delete")
        )

      assert html =~ "btn-error"
    end

    test "renders warning variant" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-warning",
          title: "Warning?",
          confirm_variant: "warning",
          on_confirm: JS.push("warn")
        )

      assert html =~ "btn-warning"
    end

    test "renders with icon" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-icon",
          title: "Danger!",
          icon: "alert-triangle",
          on_confirm: JS.push("proceed")
        )

      assert html =~ "svg"
      assert html =~ "text-error"
    end

    test "renders with custom icon_class" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-icon-class",
          title: "Info!",
          icon: "info",
          icon_class: "text-info",
          on_confirm: JS.push("ok")
        )

      assert html =~ "text-info"
    end

    test "does not render icon div when icon is nil" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-no-icon",
          title: "Simple",
          on_confirm: JS.push("ok")
        )

      refute html =~ "size-8"
    end

    test "renders escape key and click-away handlers" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-handlers",
          title: "Close me",
          on_confirm: JS.push("ok")
        )

      assert html =~ "phx-key=\"escape\""
      assert html =~ "phx-click-away"
      assert html =~ "phx-window-keydown"
    end

    test "renders modal backdrop" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-backdrop",
          title: "With Backdrop",
          on_confirm: JS.push("ok")
        )

      assert html =~ "modal-backdrop"
    end

    test "renders cancel button with ghost styling" do
      html =
        render_component(&CoreComponents.confirm_modal/1,
          id: "confirm-cancel",
          title: "Test",
          on_confirm: JS.push("ok")
        )

      assert html =~ "btn-ghost"
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

  describe "show_modal/2" do
    test "returns JS struct" do
      result = CoreComponents.show_modal("my-modal")
      assert %JS{} = result
    end

    test "accepts JS struct as first argument" do
      result = CoreComponents.show_modal(%JS{}, "my-modal")
      assert %JS{} = result
    end
  end

  describe "hide_modal/2" do
    test "returns JS struct" do
      result = CoreComponents.hide_modal("my-modal")
      assert %JS{} = result
    end

    test "accepts JS struct as first argument" do
      result = CoreComponents.hide_modal(%JS{}, "my-modal")
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
