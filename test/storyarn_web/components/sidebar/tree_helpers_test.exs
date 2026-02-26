defmodule StoryarnWeb.Components.Sidebar.TreeHelpersTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Components.Sidebar.TreeHelpers

  # ── has_children?/1 ──────────────────────────────────────────────────

  describe "has_children?/1" do
    test "returns false for nil children" do
      refute TreeHelpers.has_children?(%{children: nil})
    end

    test "returns false for empty list children" do
      refute TreeHelpers.has_children?(%{children: []})
    end

    test "returns true for non-empty children list" do
      refute TreeHelpers.has_children?(%{children: []})
      assert TreeHelpers.has_children?(%{children: [%{id: 1}]})
    end

    test "returns false when children key is missing" do
      refute TreeHelpers.has_children?(%{name: "test"})
    end

    test "returns false for non-list children value" do
      refute TreeHelpers.has_children?(%{children: "not a list"})
    end

    test "returns true for multiple children" do
      assert TreeHelpers.has_children?(%{children: [%{id: 1}, %{id: 2}]})
    end
  end

  # ── has_selected_recursive?/2 ──────────────────────────────────────

  describe "has_selected_recursive?/2" do
    test "returns false for non-binary selected_id" do
      items = [%{id: 1, children: []}]
      refute TreeHelpers.has_selected_recursive?(items, nil)
      refute TreeHelpers.has_selected_recursive?(items, 1)
    end

    test "returns true when item matches directly" do
      items = [%{id: 1, children: []}]
      assert TreeHelpers.has_selected_recursive?(items, "1")
    end

    test "returns false when no item matches" do
      items = [%{id: 1, children: []}, %{id: 2, children: []}]
      refute TreeHelpers.has_selected_recursive?(items, "99")
    end

    test "returns true when matching nested child" do
      items = [
        %{
          id: 1,
          children: [
            %{
              id: 2,
              children: [
                %{id: 3, children: []}
              ]
            }
          ]
        }
      ]

      assert TreeHelpers.has_selected_recursive?(items, "3")
    end

    test "returns false for empty list" do
      refute TreeHelpers.has_selected_recursive?([], "1")
    end

    test "matches among siblings" do
      items = [
        %{id: 1, children: []},
        %{id: 2, children: []},
        %{id: 3, children: []}
      ]

      assert TreeHelpers.has_selected_recursive?(items, "2")
    end

    test "handles items without children key" do
      items = [%{id: 1}]
      refute TreeHelpers.has_selected_recursive?(items, "99")
    end

    test "matches string id conversion" do
      # id is an integer, but selected_id is a string
      items = [%{id: 42, children: []}]
      assert TreeHelpers.has_selected_recursive?(items, "42")
    end
  end
end
