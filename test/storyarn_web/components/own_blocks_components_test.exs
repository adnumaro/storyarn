defmodule StoryarnWeb.SheetLive.Components.OwnBlocksComponentsTest do
  @moduledoc """
  Tests for OwnBlocksComponents: own_properties_label, blocks_container, add_block_prompt.
  Tests both unit-level rendering (render_component) and integration through the LiveView.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Components.OwnBlocksComponents

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sheet_path(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_sheet(conn, workspace, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_path(workspace, project, sheet))
    html = render_async(view, 500)
    {:ok, view, html}
  end

  defp send_to_content_tab(view, event, params \\ %{}) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  # ===========================================================================
  # Unit tests — own_properties_label/1
  # ===========================================================================

  describe "own_properties_label/1" do
    test "renders label when show is true" do
      html = render_component(&OwnBlocksComponents.own_properties_label/1, show: true)

      assert html =~ "Own Properties"
      assert html =~ "uppercase"
      assert html =~ "tracking-wider"
    end

    test "does not render label when show is false" do
      html = render_component(&OwnBlocksComponents.own_properties_label/1, show: false)

      refute html =~ "Own Properties"
    end
  end

  # ===========================================================================
  # Unit tests — add_block_prompt/1
  # ===========================================================================

  describe "add_block_prompt/1 — can_edit true" do
    test "renders prompt text when menu is hidden" do
      html =
        render_component(&OwnBlocksComponents.add_block_prompt/1,
          can_edit: true,
          show_block_menu: false,
          block_scope: "self",
          target: nil
        )

      assert html =~ "Type / to add a block"
      assert html =~ "show_block_menu"
    end

    test "renders block menu when show_block_menu is true" do
      html =
        render_component(&OwnBlocksComponents.add_block_prompt/1,
          can_edit: true,
          show_block_menu: true,
          block_scope: "self",
          target: nil
        )

      # When block menu is shown, the prompt text should be hidden
      refute html =~ "Type / to add a block"

      # Block menu should render block type options
      assert html =~ "Text"
      assert html =~ "Number"
      assert html =~ "Boolean"
      assert html =~ "Select"
      assert html =~ "Divider"
    end

    test "passes block_scope to block menu" do
      html =
        render_component(&OwnBlocksComponents.add_block_prompt/1,
          can_edit: true,
          show_block_menu: true,
          block_scope: "children",
          target: nil
        )

      # The block menu should show scope selector with "children" selected
      assert html =~ "This sheet and all children"
    end
  end

  describe "add_block_prompt/1 — can_edit false" do
    test "does not render anything when cannot edit" do
      html =
        render_component(&OwnBlocksComponents.add_block_prompt/1,
          can_edit: false,
          show_block_menu: false,
          block_scope: "self",
          target: nil
        )

      refute html =~ "Type / to add a block"
      refute html =~ "show_block_menu"
    end
  end

  # ===========================================================================
  # Unit tests — blocks_container/1 (empty layouts only, blocks tested via integration)
  # ===========================================================================

  describe "blocks_container/1 — container attributes" do
    test "renders container with sortable hook when can_edit is true" do
      html =
        render_component(&OwnBlocksComponents.blocks_container/1,
          layout_items: [],
          can_edit: true,
          editing_block_id: nil,
          target: nil,
          component_id: "content-tab",
          table_data: %{},
          reference_options: []
        )

      assert html =~ "blocks-container"
      assert html =~ "ColumnSortable"
      assert html =~ ~s(data-group="blocks")
      assert html =~ ~s(data-handle=".drag-handle")
    end

    test "renders container without sortable hook when can_edit is false" do
      html =
        render_component(&OwnBlocksComponents.blocks_container/1,
          layout_items: [],
          can_edit: false,
          editing_block_id: nil,
          target: nil,
          component_id: "content-tab",
          table_data: %{},
          reference_options: []
        )

      assert html =~ "blocks-container"
      refute html =~ "ColumnSortable"
    end

    test "renders container with correct phx-target reference" do
      html =
        render_component(&OwnBlocksComponents.blocks_container/1,
          layout_items: [],
          can_edit: true,
          editing_block_id: nil,
          target: nil,
          component_id: "my-component",
          table_data: %{},
          reference_options: []
        )

      assert html =~ ~s(data-phx-target="#my-component")
    end
  end

  # ===========================================================================
  # Integration tests — through LiveView
  # ===========================================================================

  describe "own_properties_label integration — not shown without inherited blocks" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Own Blocks Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "does not show own properties label when no inherited blocks", ctx do
      _block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Name"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      refute html =~ "Own Properties"
    end
  end

  describe "own_properties_label integration — shown with inherited blocks" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Parent Sheet"})
      _inheritable = inheritable_block_fixture(parent, type: "text", label: "Inherited Name")
      child = child_sheet_fixture(project, parent, %{name: "Child Sheet"})

      %{
        project: project,
        workspace: project.workspace,
        parent: parent,
        child: child
      }
    end

    test "shows own properties label when child has inherited blocks", ctx do
      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.child)

      assert html =~ "Own Properties"
    end
  end

  describe "blocks_container integration — renders blocks" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Blocks Container Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "renders the blocks container with own blocks", ctx do
      block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Hero Name"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "blocks-container"
      assert html =~ "block-#{block.id}"
    end

    test "renders multiple blocks in order", ctx do
      block1 = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "First"}})
      block2 = block_fixture(ctx.sheet, %{type: "number", config: %{"label" => "Second"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "block-#{block1.id}"
      assert html =~ "block-#{block2.id}"
    end

    test "renders empty container when sheet has no blocks", ctx do
      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "blocks-container"
    end

    test "renders sortable hook for editors", ctx do
      _block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Test"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "ColumnSortable"
    end

    test "does not render sortable hook for viewers", %{user: user} = ctx do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Viewer Sheet"})
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Test"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, project.workspace, project, sheet)

      refute html =~ "ColumnSortable"
    end
  end

  describe "add_block_prompt integration" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Add Block Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "shows add block prompt for editors", ctx do
      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "Type / to add a block"
    end

    test "does not show add block prompt for viewers", %{user: user} = ctx do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Viewer Add Block Sheet"})

      {:ok, _view, html} = mount_sheet(ctx.conn, project.workspace, project, sheet)

      refute html =~ "Type / to add a block"
    end

    test "shows block menu on click", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "show_block_menu")
      html = render(view)

      # Block menu should be visible now, prompt text should be hidden
      refute html =~ "Type / to add a block"
    end

    test "adds a block via block menu", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})

      blocks = Sheets.list_blocks(ctx.sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "text"

      # The new block should be rendered in the container
      html = render(view)
      assert html =~ "block-#{hd(blocks).id}"
    end
  end

  describe "blocks_container integration — various block types" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Block Types Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "renders text block with label", ctx do
      _block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Character Name"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "Character Name"
    end

    test "renders number block with label", ctx do
      _block = block_fixture(ctx.sheet, %{type: "number", config: %{"label" => "Hit Points"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "Hit Points"
    end

    test "renders boolean block", ctx do
      _block = block_fixture(ctx.sheet, %{type: "boolean", config: %{"label" => "Is Alive"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "Is Alive"
    end

    test "renders select block", ctx do
      _block =
        block_fixture(ctx.sheet, %{
          type: "select",
          config: %{
            "label" => "Race",
            "options" => [
              %{"key" => "human", "value" => "Human"},
              %{"key" => "elf", "value" => "Elf"}
            ]
          }
        })

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "Race"
    end

    test "renders divider block as hr element", ctx do
      _block = block_fixture(ctx.sheet, %{type: "divider", config: %{}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "<hr"
    end

    test "renders date block", ctx do
      _block = block_fixture(ctx.sheet, %{type: "date", config: %{"label" => "Birth Date"}})

      {:ok, _view, html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      assert html =~ "Birth Date"
    end
  end

  describe "blocks_container integration — column groups" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Column Group Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "creates column group from two blocks", ctx do
      block1 = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "First Name"}})
      block2 = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Last Name"}})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Create column group via event
      send_to_content_tab(view, "create_column_group", %{
        "block_ids" => [to_string(block1.id), to_string(block2.id)]
      })

      html = render(view)

      # Should have column-group class and grid layout
      assert html =~ "column-group"
      assert html =~ "sm:grid-cols-2"
      assert html =~ "block-#{block1.id}"
      assert html =~ "block-#{block2.id}"
    end

    test "renders blocks in column group with data attributes", ctx do
      block1 = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "A"}})
      block2 = block_fixture(ctx.sheet, %{type: "number", config: %{"label" => "B"}})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "create_column_group", %{
        "block_ids" => [to_string(block1.id), to_string(block2.id)]
      })

      html = render(view)

      assert html =~ "data-column-group"
      assert html =~ "column-item"
    end
  end

  describe "blocks_container integration — hide block menu" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Hide Menu Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "hides block menu", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "show_block_menu")
      refute render(view) =~ "Type / to add a block"

      send_to_content_tab(view, "hide_block_menu")
      assert render(view) =~ "Type / to add a block"
    end
  end

  describe "add_block_prompt integration — block scope" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Block Scope Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "can set block scope before adding", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Set scope to children
      send_to_content_tab(view, "set_block_scope", %{"scope" => "children"})

      # Show menu and add block
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "number"})

      blocks = Sheets.list_blocks(ctx.sheet.id)
      assert length(blocks) == 1
      block = hd(blocks)
      assert block.type == "number"
      assert block.scope == "children"
    end
  end
end
