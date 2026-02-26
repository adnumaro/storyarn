defmodule StoryarnWeb.Components.TreeComponentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

  alias StoryarnWeb.Components.TreeComponents

  # =============================================================================
  # tree_node/1
  # =============================================================================

  describe "tree_node/1 — basic rendering" do
    test "renders label text" do
      html = render_component(&TreeComponents.tree_node/1, id: "node-1", label: "Characters")
      assert html =~ "Characters"
    end

    test "renders tree-node class" do
      html = render_component(&TreeComponents.tree_node/1, id: "node-1", label: "Test")
      assert html =~ "tree-node"
    end

    test "renders custom class" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Test",
          class: "my-custom"
        )

      assert html =~ "my-custom"
    end

    test "renders data attributes for item_id and item_name" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Test",
          item_id: "abc-123",
          item_name: "My Item"
        )

      assert html =~ ~s(data-item-id="abc-123")
      assert html =~ ~s(data-item-name="My Item")
    end
  end

  describe "tree_node/1 — has_children toggle" do
    test "shows expand/collapse button when has_children is true" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Parent",
          has_children: true
        )

      assert html =~ "tree-toggle-node-1"
      assert html =~ "TreeToggle"
      assert html =~ "chevron"
    end

    test "shows spacer when has_children is false (default)" do
      html = render_component(&TreeComponents.tree_node/1, id: "node-1", label: "Leaf Node")
      # Should NOT have the toggle button
      refute html =~ "TreeToggle"
      # Should have a spacer span with w-5
      assert html =~ "w-5 shrink-0"
    end

    test "renders children container when has_children is true" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Parent",
          has_children: true
        )

      assert html =~ "tree-content-node-1"
      assert html =~ "data-sortable-container"
    end

    test "does not render children container when has_children is false" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Leaf",
          has_children: false
        )

      refute html =~ "tree-content-node-1"
      refute html =~ "data-sortable-container"
    end
  end

  describe "tree_node/1 — expanded/collapsed" do
    test "children container is visible when expanded" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Open",
          has_children: true,
          expanded: true
        )

      # The chevron should have rotate-90 class
      assert html =~ "rotate-90"
      # The children container should NOT have hidden class
      assert html =~ ~s(id="tree-content-node-1")
      # pl-5 is always present on children container; "hidden" should not be
      refute html =~ ~r/tree-content-node-1[^>]*hidden/
    end

    test "children container is hidden when collapsed" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Closed",
          has_children: true,
          expanded: false
        )

      # The chevron should NOT have rotate-90 class
      refute html =~ "rotate-90"
      # The children container should have hidden class
      assert html =~ "hidden"
    end
  end

  describe "tree_node/1 — href vs no href" do
    test "renders link when href is provided" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Linked Node",
          href: "/projects/1/sheets"
        )

      assert html =~ "/projects/1/sheets"
      assert html =~ "hover:bg-base-300"
    end

    test "renders div when href is nil" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Static Node"
        )

      # Should not have a link to navigate to
      refute html =~ "data-navigate"
      assert html =~ "Static Node"
    end
  end

  describe "tree_node/1 — badge" do
    test "renders badge when provided" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "With Badge",
          badge: 42
        )

      assert html =~ "badge"
      assert html =~ "42"
    end

    test "does not render badge when nil" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "No Badge"
        )

      refute html =~ "badge-ghost"
    end

    test "renders badge with href link" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Linked Badge",
          href: "/test",
          badge: 7
        )

      assert html =~ "badge"
      assert html =~ "7"
    end
  end

  describe "tree_node/1 — can_drag" do
    test "adds cursor-grab class when can_drag is true" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Draggable",
          can_drag: true
        )

      assert html =~ "cursor-grab"
    end

    test "does not add cursor-grab class when can_drag is false" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Not Draggable",
          can_drag: false
        )

      refute html =~ "cursor-grab"
    end
  end

  describe "tree_node/1 — icon variants (via tree_icon)" do
    test "renders avatar image when avatar_url is provided" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Avatar Node",
          avatar_url: "https://example.com/avatar.png"
        )

      assert html =~ "<img"
      assert html =~ "https://example.com/avatar.png"
      assert html =~ "rounded"
    end

    test "renders icon_text when provided and not excluded" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Emoji Node",
          icon_text: "CH"
        )

      assert html =~ "CH"
      # Should NOT have an <img> tag
      refute html =~ "<img"
    end

    test "does not render icon_text when value is empty string" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Empty Icon Text",
          icon_text: ""
        )

      # Should fall through to default file icon
      assert html =~ "opacity-60"
    end

    test "does not render icon_text when value is 'sheet'" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Sheet Excluded",
          icon_text: "sheet"
        )

      # "sheet" is excluded, so should fall through to default file icon
      assert html =~ "opacity-60"
    end

    test "renders named icon when icon is provided" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Icon Node",
          icon: "user"
        )

      # Should render an SVG icon (not img, not icon_text)
      assert html =~ "svg"
      refute html =~ "<img"
    end

    test "renders icon with color style" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Colored Icon",
          icon: "user",
          color: "#3b82f6"
        )

      assert html =~ "color: #3b82f6"
    end

    test "renders default file icon when no icon props are set" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Default Icon"
        )

      # Default icon has opacity-60 class
      assert html =~ "opacity-60"
    end

    test "avatar_url takes priority over icon and icon_text" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Priority Test",
          avatar_url: "https://example.com/avatar.png",
          icon: "user",
          icon_text: "TE"
        )

      assert html =~ "<img"
      assert html =~ "https://example.com/avatar.png"
    end

    test "icon_text takes priority over icon" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Priority Test",
          icon: "user",
          icon_text: "AB"
        )

      # icon_text "AB" is not in the exclusion list, so it renders
      assert html =~ "AB"
    end
  end

  describe "tree_node/1 — slots" do
    test "renders inner_block content when has_children" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <TreeComponents.tree_node id="node-1" label="Parent" has_children expanded>
          <p>Child content here</p>
        </TreeComponents.tree_node>
        """)

      assert html =~ "Child content here"
    end

    test "renders actions slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <TreeComponents.tree_node id="node-1" label="With Actions">
          <:actions>
            <button class="test-action-btn">Add</button>
          </:actions>
        </TreeComponents.tree_node>
        """)

      assert html =~ "test-action-btn"
      assert html =~ "Add"
    end

    test "renders menu slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <TreeComponents.tree_node id="node-1" label="With Menu">
          <:menu>
            <div class="test-menu">Menu Content</div>
          </:menu>
        </TreeComponents.tree_node>
        """)

      assert html =~ "test-menu"
      assert html =~ "Menu Content"
    end

    test "renders actions and menu together with hover container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <TreeComponents.tree_node id="node-1" label="Both Slots">
          <:actions>
            <button>Act</button>
          </:actions>
          <:menu>
            <div>Menu</div>
          </:menu>
        </TreeComponents.tree_node>
        """)

      assert html =~ "group-hover:opacity-100"
      assert html =~ "Act"
      assert html =~ "Menu"
    end

    test "does not render hover container when no actions or menu" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "No Slots"
        )

      refute html =~ "group-hover:opacity-100"
    end
  end

  describe "tree_node/1 — children container data attributes" do
    test "renders data-parent-id on children container" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Parent",
          has_children: true,
          item_id: "parent-uuid"
        )

      assert html =~ ~s(data-parent-id="parent-uuid")
    end
  end

  # =============================================================================
  # tree_leaf/1
  # =============================================================================

  describe "tree_leaf/1 — basic rendering" do
    test "renders label and href" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "My Leaf",
          href: "/projects/1/sheets/2"
        )

      assert html =~ "My Leaf"
      assert html =~ "/projects/1/sheets/2"
    end

    test "renders tree-leaf class" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Test",
          href: "/test"
        )

      assert html =~ "tree-leaf"
    end

    test "renders custom class" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Test",
          href: "/test",
          class: "extra-class"
        )

      assert html =~ "extra-class"
    end

    test "renders data attributes for item_id and item_name" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Test",
          href: "/test",
          item_id: "leaf-id",
          item_name: "Leaf Name"
        )

      assert html =~ ~s(data-item-id="leaf-id")
      assert html =~ ~s(data-item-name="Leaf Name")
    end

    test "renders alignment spacer" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Test",
          href: "/test"
        )

      # Spacer span to align with tree_node expand/collapse area
      assert html =~ "w-5 shrink-0"
    end
  end

  describe "tree_leaf/1 — active state" do
    test "applies active styling when active is true" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Active Leaf",
          href: "/test",
          active: true
        )

      assert html =~ "bg-base-300"
      assert html =~ "font-medium"
    end

    test "applies hover styling when active is false" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Inactive Leaf",
          href: "/test",
          active: false
        )

      assert html =~ "hover:bg-base-300"
      refute html =~ "font-medium"
    end
  end

  describe "tree_leaf/1 — can_drag" do
    test "adds cursor-grab class when can_drag is true" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Draggable",
          href: "/test",
          can_drag: true
        )

      assert html =~ "cursor-grab"
    end

    test "does not add cursor-grab when can_drag is false" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Static",
          href: "/test",
          can_drag: false
        )

      refute html =~ "cursor-grab"
    end
  end

  describe "tree_leaf/1 — icon variants (via tree_icon)" do
    test "renders avatar image when avatar_url is provided" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Avatar Leaf",
          href: "/test",
          avatar_url: "https://example.com/photo.jpg"
        )

      assert html =~ "<img"
      assert html =~ "https://example.com/photo.jpg"
    end

    test "renders icon_text when provided" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Text Leaf",
          href: "/test",
          icon_text: "FL"
        )

      assert html =~ "FL"
    end

    test "renders named icon" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Icon Leaf",
          href: "/test",
          icon: "box"
        )

      assert html =~ "svg"
    end

    test "renders icon with color" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Colored Leaf",
          href: "/test",
          icon: "box",
          color: "#ff0000"
        )

      assert html =~ "color: #ff0000"
    end

    test "renders default file icon when no icon props" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Default Leaf",
          href: "/test"
        )

      assert html =~ "opacity-60"
    end

    test "icon_text 'sheet' falls through to default" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Sheet Leaf",
          href: "/test",
          icon_text: "sheet"
        )

      # "sheet" is excluded, falls through to default file icon
      assert html =~ "opacity-60"
    end
  end

  describe "tree_leaf/1 — slots" do
    test "renders actions slot with hover container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <TreeComponents.tree_leaf label="Leaf" href="/test">
          <:actions>
            <button class="leaf-action">Edit</button>
          </:actions>
        </TreeComponents.tree_leaf>
        """)

      assert html =~ "leaf-action"
      assert html =~ "Edit"
      assert html =~ "group-hover:opacity-100"
    end

    test "renders menu slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <TreeComponents.tree_leaf label="Leaf" href="/test">
          <:menu>
            <div class="leaf-menu">Options</div>
          </:menu>
        </TreeComponents.tree_leaf>
        """)

      assert html =~ "leaf-menu"
      assert html =~ "Options"
    end

    test "does not render hover container when no slots" do
      html =
        render_component(&TreeComponents.tree_leaf/1,
          label: "Simple Leaf",
          href: "/test"
        )

      refute html =~ "group-hover:opacity-100"
    end
  end

  # =============================================================================
  # tree_section/1
  # =============================================================================

  describe "tree_section/1" do
    test "renders section label" do
      html = render_component(&TreeComponents.tree_section/1, label: "ENTITIES")
      assert html =~ "ENTITIES"
    end

    test "applies uppercase styling" do
      html = render_component(&TreeComponents.tree_section/1, label: "Flows")
      assert html =~ "uppercase"
    end

    test "applies tracking and font styling" do
      html = render_component(&TreeComponents.tree_section/1, label: "Test")
      assert html =~ "tracking-wide"
      assert html =~ "font-semibold"
      assert html =~ "text-xs"
    end

    test "applies muted text color" do
      html = render_component(&TreeComponents.tree_section/1, label: "Test")
      assert html =~ "text-base-content/50"
    end

    test "renders custom class" do
      html =
        render_component(&TreeComponents.tree_section/1,
          label: "Test",
          class: "mt-4"
        )

      assert html =~ "mt-4"
    end
  end

  # =============================================================================
  # tree_link/1
  # =============================================================================

  describe "tree_link/1 — basic rendering" do
    test "renders label and href" do
      html =
        render_component(&TreeComponents.tree_link/1,
          label: "Settings",
          href: "/projects/1/settings"
        )

      assert html =~ "Settings"
      assert html =~ "/projects/1/settings"
    end

    test "renders as a link element" do
      html =
        render_component(&TreeComponents.tree_link/1,
          label: "Dashboard",
          href: "/dashboard"
        )

      assert html =~ "/dashboard"
    end

    test "renders custom class" do
      html =
        render_component(&TreeComponents.tree_link/1,
          label: "Test",
          href: "/test",
          class: "mt-2"
        )

      assert html =~ "mt-2"
    end
  end

  describe "tree_link/1 — active state" do
    test "applies active styling when active is true" do
      html =
        render_component(&TreeComponents.tree_link/1,
          label: "Active Link",
          href: "/test",
          active: true
        )

      assert html =~ "bg-base-300"
      assert html =~ "font-medium"
    end

    test "applies hover styling when active is false" do
      html =
        render_component(&TreeComponents.tree_link/1,
          label: "Inactive Link",
          href: "/test",
          active: false
        )

      assert html =~ "hover:bg-base-300"
      refute html =~ "font-medium"
    end
  end

  describe "tree_link/1 — icon" do
    test "renders icon when provided" do
      html =
        render_component(&TreeComponents.tree_link/1,
          label: "With Icon",
          href: "/test",
          icon: "settings"
        )

      assert html =~ "svg"
    end

    test "does not render icon when not provided" do
      html =
        render_component(&TreeComponents.tree_link/1,
          label: "No Icon",
          href: "/test"
        )

      # The link should not contain any icon SVG
      # Just the label in a span
      assert html =~ "<span>"
      assert html =~ "No Icon"
    end
  end

  # =============================================================================
  # Integration: tree_icon priority and edge cases
  # =============================================================================

  describe "tree_icon priority through tree_node" do
    test "icon_text nil falls through to icon" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Test",
          icon_text: nil,
          icon: "star"
        )

      # Should render the star icon SVG, not icon_text
      assert html =~ "svg"
    end

    test "all icon props nil renders default file icon" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Test",
          avatar_url: nil,
          icon_text: nil,
          icon: nil
        )

      assert html =~ "opacity-60"
    end

    test "icon_text with valid value renders text not icon" do
      html =
        render_component(&TreeComponents.tree_node/1,
          id: "node-1",
          label: "Test",
          icon_text: "XY",
          icon: "star"
        )

      assert html =~ "XY"
    end
  end
end
