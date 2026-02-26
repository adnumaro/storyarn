defmodule StoryarnWeb.SheetLive.Components.ChildrenSheetsSectionTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.SheetLive.Components.ChildrenSheetsSection

  # ── Helpers ──────────────────────────────────────────────────────────

  defp render_section(overrides) do
    assigns =
      Map.merge(
        %{
          children: [],
          workspace: %{slug: "my-workspace"},
          project: %{slug: "my-project"}
        },
        overrides
      )

    render_component(&ChildrenSheetsSection.children_sheets_section/1, assigns)
  end

  defp make_child(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        name: "Child Sheet",
        avatar_asset: nil
      },
      attrs
    )
  end

  # ── Section heading ─────────────────────────────────────────────────

  describe "section heading" do
    test "renders Subsheets heading" do
      html = render_section(%{children: [make_child()]})

      assert html =~ "Subsheets"
    end

    test "renders section even with empty children list" do
      html = render_section(%{})

      assert html =~ "Subsheets"
    end
  end

  # ── Child sheet links ───────────────────────────────────────────────

  describe "child sheet links" do
    test "renders each child as a navigable link" do
      children = [
        make_child(%{id: "id-1", name: "Character Sheet"}),
        make_child(%{id: "id-2", name: "Inventory Sheet"})
      ]

      html = render_section(%{children: children})

      assert html =~ "Character Sheet"
      assert html =~ "Inventory Sheet"
    end

    test "link navigates to correct sheet URL" do
      child = make_child(%{id: "child-uuid-123", name: "Stats"})

      html =
        render_section(%{
          children: [child],
          workspace: %{slug: "ws-one"},
          project: %{slug: "proj-alpha"}
        })

      assert html =~ "/workspaces/ws-one/projects/proj-alpha/sheets/child-uuid-123"
    end

    test "renders child names correctly" do
      children = [
        make_child(%{name: "First Child"}),
        make_child(%{name: "Second Child"}),
        make_child(%{name: "Third Child"})
      ]

      html = render_section(%{children: children})

      assert html =~ "First Child"
      assert html =~ "Second Child"
      assert html =~ "Third Child"
    end

    test "renders no links for empty children list" do
      html = render_section(%{})

      refute html =~ "/sheets/"
    end
  end

  # ── Avatar rendering ────────────────────────────────────────────────

  describe "avatar rendering" do
    test "renders sheet_avatar for child with no avatar asset" do
      children = [make_child(%{name: "No Avatar", avatar_asset: nil})]

      html = render_section(%{children: children})

      # Fallback avatar should show initials or placeholder
      assert html =~ "No Avatar"
    end

    test "renders sheet_avatar for child with avatar asset" do
      avatar = %{id: "asset-1", url: "/uploads/avatar.png"}
      children = [make_child(%{name: "Has Avatar", avatar_asset: avatar})]

      html = render_section(%{children: children})

      assert html =~ "Has Avatar"
    end
  end
end
