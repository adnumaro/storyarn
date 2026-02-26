defmodule StoryarnWeb.ScreenplayLive.Components.ScreenplayToolbarTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Storyarn.Screenplays.Screenplay
  alias StoryarnWeb.ScreenplayLive.Components.ScreenplayToolbar

  defp make_screenplay(overrides \\ %{}) do
    struct(
      Screenplay,
      Map.merge(
        %{id: 1, name: "Test Screenplay", linked_flow_id: nil, draft_of_id: nil},
        overrides
      )
    )
  end

  defp base_assigns(overrides) do
    Map.merge(
      %{
        screenplay: make_screenplay(),
        elements: [],
        workspace: %{slug: "test-ws"},
        project: %{slug: "test-proj"},
        read_mode: false,
        can_edit: true,
        link_status: :unlinked,
        linked_flow: nil
      },
      overrides
    )
  end

  defp render_toolbar(overrides \\ %{}) do
    render_component(&ScreenplayToolbar.screenplay_toolbar/1, base_assigns(overrides))
  end

  # =============================================================================
  # Basic rendering
  # =============================================================================

  describe "screenplay_toolbar/1 — basic" do
    test "renders toolbar with screenplay name" do
      html = render_toolbar()
      assert html =~ "Test Screenplay"
      assert html =~ "screenplay-toolbar"
    end

    test "shows element count" do
      html = render_toolbar(%{elements: [%{}, %{}, %{}]})
      assert html =~ "3"
    end

    test "shows editable title when can_edit" do
      html = render_toolbar(%{can_edit: true})
      assert html =~ "contenteditable"
    end

    test "shows non-editable title when cannot edit" do
      html = render_toolbar(%{can_edit: false})
      refute html =~ "contenteditable"
    end
  end

  # =============================================================================
  # Draft badge
  # =============================================================================

  describe "screenplay_toolbar/1 — draft badge" do
    test "does not show draft badge for non-draft screenplay" do
      html = render_toolbar(%{screenplay: make_screenplay(%{draft_of_id: nil})})
      refute html =~ "Draft"
    end
  end

  # =============================================================================
  # Read mode toggle
  # =============================================================================

  describe "screenplay_toolbar/1 — read mode" do
    test "shows book icon when not in read mode" do
      html = render_toolbar(%{read_mode: false})
      assert html =~ "book-open"
    end

    test "shows pencil icon when in read mode" do
      html = render_toolbar(%{read_mode: true})
      assert html =~ "pencil"
    end

    test "read mode button has active class when in read mode" do
      html = render_toolbar(%{read_mode: true})
      assert html =~ "sp-toolbar-btn-active"
    end
  end

  # =============================================================================
  # Export/Import buttons
  # =============================================================================

  describe "screenplay_toolbar/1 — export/import" do
    test "shows export button with download link" do
      html = render_toolbar()
      assert html =~ "upload"
      assert html =~ "export/fountain"
    end

    test "shows import button when can_edit" do
      html = render_toolbar(%{can_edit: true})
      assert html =~ "screenplay-import-btn"
    end

    test "hides import button when cannot edit" do
      html = render_toolbar(%{can_edit: false})
      refute html =~ "screenplay-import-btn"
    end
  end

  # =============================================================================
  # Link status — :unlinked
  # =============================================================================

  describe "screenplay_toolbar/1 — unlinked" do
    test "shows Create Flow button when unlinked and can_edit" do
      html = render_toolbar(%{link_status: :unlinked, can_edit: true})
      assert html =~ "Create Flow"
      assert html =~ "create_flow_from_screenplay"
    end

    test "hides Create Flow button when unlinked and cannot edit" do
      html = render_toolbar(%{link_status: :unlinked, can_edit: false})
      refute html =~ "Create Flow"
    end
  end

  # =============================================================================
  # Link status — :linked
  # =============================================================================

  describe "screenplay_toolbar/1 — linked" do
    test "shows linked flow name" do
      html =
        render_toolbar(%{
          link_status: :linked,
          linked_flow: %{name: "Main Flow"}
        })

      assert html =~ "Main Flow"
      assert html =~ "sp-sync-linked"
    end

    test "shows sync buttons when linked and can_edit" do
      html =
        render_toolbar(%{
          link_status: :linked,
          linked_flow: %{name: "Main Flow"},
          can_edit: true
        })

      assert html =~ "To Flow"
      assert html =~ "From Flow"
      assert html =~ "sync_to_flow"
      assert html =~ "sync_from_flow"
      assert html =~ "unlink_flow"
    end

    test "hides sync buttons when linked but cannot edit" do
      html =
        render_toolbar(%{
          link_status: :linked,
          linked_flow: %{name: "Main Flow"},
          can_edit: false
        })

      refute html =~ "To Flow"
      refute html =~ "From Flow"
    end
  end

  # =============================================================================
  # Link status — :flow_deleted / :flow_missing
  # =============================================================================

  describe "screenplay_toolbar/1 — flow_deleted" do
    test "shows warning badge for deleted flow" do
      html = render_toolbar(%{link_status: :flow_deleted, can_edit: true})
      assert html =~ "sp-sync-warning"
      assert html =~ "alert-triangle"
      assert html =~ "Flow trashed"
    end

    test "shows unlink button for deleted flow" do
      html = render_toolbar(%{link_status: :flow_deleted, can_edit: true})
      assert html =~ "Unlink"
      assert html =~ "unlink_flow"
    end
  end

  describe "screenplay_toolbar/1 — flow_missing" do
    test "shows warning badge for missing flow" do
      html = render_toolbar(%{link_status: :flow_missing, can_edit: true})
      assert html =~ "sp-sync-warning"
      assert html =~ "Flow missing"
    end

    test "hides unlink button when cannot edit" do
      html = render_toolbar(%{link_status: :flow_missing, can_edit: false})
      refute html =~ "Unlink"
    end
  end
end
