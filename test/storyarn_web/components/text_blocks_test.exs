defmodule StoryarnWeb.Components.BlockComponents.TextBlocksTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.Components.BlockComponents.TextBlocks

  # =============================================================================
  # Helper to build a block-like struct for render_component
  # =============================================================================

  defp build_block(attrs \\ %{}) do
    defaults = %{
      id: System.unique_integer([:positive]),
      type: "text",
      config: %{"label" => "My Label", "placeholder" => "Enter text..."},
      value: %{"content" => ""},
      is_constant: false,
      inherited_from_block_id: nil
    }

    struct!(Storyarn.Sheets.Block, Map.merge(defaults, attrs))
  end

  # =============================================================================
  # text_block/1
  # =============================================================================

  describe "text_block/1" do
    test "renders label from config" do
      block = build_block(%{config: %{"label" => "Character Name", "placeholder" => ""}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      assert html =~ "Character Name"
    end

    test "renders text input when can_edit is true" do
      block =
        build_block(%{
          config: %{"label" => "Name", "placeholder" => "Enter name..."},
          value: %{"content" => "Jaime"}
        })

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: true)

      assert html =~ "<input"
      assert html =~ "type=\"text\""
      assert html =~ "value=\"Jaime\""
      assert html =~ "Enter name..."
      assert html =~ "phx-blur=\"update_block_value\""
      assert html =~ "phx-value-id=\"#{block.id}\""
    end

    test "renders read-only content when can_edit is false" do
      block = build_block(%{value: %{"content" => "Hello World"}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      refute html =~ "<input"
      assert html =~ "Hello World"
    end

    test "renders dash placeholder when content is empty and not editable" do
      block = build_block(%{value: %{"content" => ""}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      assert html =~ "text-base-content/40"
      assert html =~ "-"
    end

    test "does not show dash placeholder when content is present" do
      block = build_block(%{value: %{"content" => "Some text"}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      refute html =~ "text-base-content/40"
      assert html =~ "Some text"
    end

    test "renders constant indicator when is_constant is true" do
      block = build_block(%{is_constant: true, config: %{"label" => "Constant Field"}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      assert html =~ "Constant"
    end

    test "does not render constant indicator when is_constant is false" do
      block = build_block(%{is_constant: false, config: %{"label" => "Variable Field"}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      refute html =~ "Constant"
    end

    test "handles nil values gracefully" do
      block = build_block(%{config: %{}, value: %{}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      # Should still render without error, showing dash for empty content
      assert html =~ "-"
    end

    test "renders with target attribute for LiveComponent context" do
      block = build_block()

      html =
        render_component(&TextBlocks.text_block/1,
          block: block,
          can_edit: true,
          target: "#content-tab"
        )

      assert html =~ "phx-target=\"#content-tab\""
    end

    test "does not render input when not editable" do
      block = build_block(%{value: %{"content" => "Read only text"}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      refute html =~ "phx-blur"
      refute html =~ "update_block_value"
    end

    test "renders empty label gracefully" do
      block = build_block(%{config: %{"label" => ""}})

      html = render_component(&TextBlocks.text_block/1, block: block, can_edit: false)

      # Empty label should not render the label element
      refute html =~ "<label"
    end
  end

  # =============================================================================
  # rich_text_block/1
  # =============================================================================

  describe "rich_text_block/1" do
    test "renders TiptapEditor hook container" do
      block = build_block(%{type: "rich_text", config: %{"label" => "Description"}})

      html = render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: true)

      assert html =~ "phx-hook=\"TiptapEditor\""
      assert html =~ "id=\"tiptap-#{block.id}\""
    end

    test "renders label from config" do
      block = build_block(%{type: "rich_text", config: %{"label" => "Bio"}})

      html = render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: false)

      assert html =~ "Bio"
    end

    test "passes content as data attribute" do
      block =
        build_block(%{
          type: "rich_text",
          value: %{"content" => "<p>Rich content</p>"}
        })

      html = render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: true)

      assert html =~ "data-content=\"&lt;p&gt;Rich content&lt;/p&gt;\""
    end

    test "sets editable data attribute based on can_edit" do
      block = build_block(%{type: "rich_text"})

      html_editable =
        render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: true)

      html_readonly =
        render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: false)

      assert html_editable =~ "data-editable=\"true\""
      assert html_readonly =~ "data-editable=\"false\""
    end

    test "passes block id as data attribute" do
      block = build_block(%{type: "rich_text"})

      html = render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: true)

      assert html =~ "data-block-id=\"#{block.id}\""
    end

    test "renders constant indicator when is_constant is true" do
      block =
        build_block(%{
          type: "rich_text",
          is_constant: true,
          config: %{"label" => "Fixed Bio"}
        })

      html = render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: false)

      assert html =~ "Constant"
    end

    test "sets phx-target selector when target is provided" do
      block = build_block(%{type: "rich_text"})

      html =
        render_component(&TextBlocks.rich_text_block/1,
          block: block,
          can_edit: true,
          target: "#content-tab"
        )

      assert html =~ "data-phx-target=\"#content-tab\""
    end

    test "sets nil phx-target when no target provided" do
      block = build_block(%{type: "rich_text"})

      html =
        render_component(&TextBlocks.rich_text_block/1,
          block: block,
          can_edit: true,
          target: nil
        )

      # No target selector should be set
      refute html =~ "data-phx-target=\"#"
    end

    test "uses phx-update ignore to prevent LiveView re-rendering" do
      block = build_block(%{type: "rich_text"})

      html = render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: true)

      assert html =~ "phx-update=\"ignore\""
    end

    test "handles empty content" do
      block =
        build_block(%{type: "rich_text", value: %{"content" => ""}})

      html = render_component(&TextBlocks.rich_text_block/1, block: block, can_edit: true)

      assert html =~ "data-content=\"\""
    end
  end

  # =============================================================================
  # number_block/1
  # =============================================================================

  describe "number_block/1" do
    test "renders number input when can_edit is true" do
      block =
        build_block(%{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"},
          value: %{"content" => 100}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: true)

      assert html =~ "<input"
      assert html =~ "type=\"number\""
      assert html =~ "value=\"100\""
      assert html =~ "phx-blur=\"update_block_value\""
    end

    test "renders label from config" do
      block =
        build_block(%{
          type: "number",
          config: %{"label" => "Armor Class"}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: false)

      assert html =~ "Armor Class"
    end

    test "renders read-only value when can_edit is false" do
      block =
        build_block(%{
          type: "number",
          value: %{"content" => 42}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: false)

      refute html =~ "<input"
      assert html =~ "42"
    end

    test "renders dash when content is nil and not editable" do
      block =
        build_block(%{
          type: "number",
          value: %{"content" => nil}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: false)

      assert html =~ "text-base-content/40"
      assert html =~ "-"
    end

    test "renders 0 value correctly (not as dash)" do
      block =
        build_block(%{
          type: "number",
          value: %{"content" => 0}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: false)

      assert html =~ "0"
      refute html =~ "text-base-content/40"
    end

    test "uses placeholder from config" do
      block =
        build_block(%{
          type: "number",
          config: %{"label" => "HP", "placeholder" => "100"}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: true)

      assert html =~ "placeholder=\"100\""
    end

    test "defaults placeholder to 0 when not configured" do
      block =
        build_block(%{
          type: "number",
          config: %{"label" => "HP"}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: true)

      assert html =~ "placeholder=\"0\""
    end

    test "applies min, max, and step constraints from config" do
      block =
        build_block(%{
          type: "number",
          config: %{
            "label" => "Score",
            "min" => 0,
            "max" => 100,
            "step" => 5
          }
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: true)

      assert html =~ "min=\"0\""
      assert html =~ "max=\"100\""
      assert html =~ "step=\"5\""
    end

    test "defaults step to any when not configured" do
      block =
        build_block(%{
          type: "number",
          config: %{"label" => "Amount"}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: true)

      assert html =~ "step=\"any\""
    end

    test "renders constant indicator when is_constant is true" do
      block =
        build_block(%{
          type: "number",
          is_constant: true,
          config: %{"label" => "Max HP"}
        })

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: false)

      assert html =~ "Constant"
    end

    test "passes block id for phx-value-id" do
      block = build_block(%{type: "number"})

      html = render_component(&TextBlocks.number_block/1, block: block, can_edit: true)

      assert html =~ "phx-value-id=\"#{block.id}\""
    end

    test "passes target for phx-target" do
      block = build_block(%{type: "number"})

      html =
        render_component(&TextBlocks.number_block/1,
          block: block,
          can_edit: true,
          target: "#content-tab"
        )

      assert html =~ "phx-target=\"#content-tab\""
    end
  end

  # =============================================================================
  # Integration: text blocks render inside sheet show LiveView
  # =============================================================================

  describe "text blocks in LiveView" do
    setup :register_and_log_in_user

    test "text block renders in sheet show page", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Character"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Full Name", "placeholder" => "Enter name..."},
          value: %{"content" => "Jaime Lannister"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)

      assert html =~ "Full Name"
      assert html =~ "Jaime Lannister"
    end

    test "number block renders in sheet show page", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Stats"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health Points", "placeholder" => "0"},
          value: %{"content" => 100}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)

      assert html =~ "Health Points"
      assert html =~ "100"
    end

    test "rich text block renders in sheet show page", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Character"})

      _block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Biography"},
          value: %{"content" => "<p>A brave knight</p>"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)

      assert html =~ "Biography"
      assert html =~ "TiptapEditor"
    end

    test "editable text block shows input for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Character"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Nickname", "placeholder" => "Enter nickname..."},
          value: %{"content" => ""}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)

      assert html =~ "type=\"text\""
      assert html =~ "Enter nickname..."
      assert html =~ "update_block_value"
    end

    test "read-only text block for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Character"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name", "placeholder" => ""},
          value: %{"content" => "Cersei"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)

      assert html =~ "Cersei"
      # Viewer should not see editable input
      refute html =~ "phx-blur=\"update_block_value\""
    end

    test "multiple blocks of different types render correctly", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Multi-Block Sheet"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Text Field", "placeholder" => ""},
        value: %{"content" => "Alpha"}
      })

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Number Field", "placeholder" => "0"},
        value: %{"content" => 42}
      })

      block_fixture(sheet, %{
        type: "rich_text",
        config: %{"label" => "Rich Field"},
        value: %{"content" => "<p>Beta</p>"}
      })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)

      assert html =~ "Text Field"
      assert html =~ "Alpha"
      assert html =~ "Number Field"
      assert html =~ "42"
      assert html =~ "Rich Field"
    end
  end
end
