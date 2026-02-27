defmodule StoryarnWeb.ScreenplayLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo

  # Handler behavior tests live in handlers/element_handlers_test.exs

  describe "Show" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp show_url(project, screenplay) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
    end

    # -------------------------------------------------------------------------
    # Rendering
    # -------------------------------------------------------------------------

    test "renders screenplay page container", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project, %{name: "My Script"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(id="screenplay-page")
      assert html =~ "screenplay-page"
    end

    test "renders element content when elements exist", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "He walks into the room."})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "He walks into the room."
    end

    test "shows empty state when no elements", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Empty screenplay renders the unified TipTap editor (placeholder is client-side)
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ ~s(phx-hook="ScreenplayEditor")
    end

    test "text elements are embedded in editor JSON with correct types", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY"})
      element_fixture(screenplay, %{type: "character", content: "JOHN"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Text elements are in the unified TipTap editor JSON (data-content)
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "sceneHeading"
      assert html =~ "INT. OFFICE - DAY"
      assert html =~ "JOHN"
    end

    test "text element data is embedded in editor JSON", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "She runs."})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Text element data is in the TipTap editor JSON (data-content)
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "She runs."
      assert html =~ "elementId"
      assert html =~ to_string(el.id)
    end

    test "flow marker blocks are embedded in editor JSON as atom nodes", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "hub_marker", content: ""})
      element_fixture(screenplay, %{type: "jump_marker", content: ""})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Stub types are now atom nodes inside the TipTap editor JSON
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "hubMarker"
      assert html =~ "jumpMarker"
    end

    test "page break is embedded in editor JSON", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "page_break", content: ""})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Page break is an atom node in the TipTap editor JSON
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "pageBreak"
    end

    test "elements render as editable when user has edit permission", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Editable."})
      element_fixture(screenplay, %{type: "character", content: "JOHN"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Unified TipTap editor replaces per-element hooks
      assert html =~ ~s(phx-hook="ScreenplayEditor")
      assert html =~ ~s(data-can-edit="true")
    end

    test "toolbar renders screenplay name", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project, %{name: "My Great Script"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(id="screenplay-toolbar")
      assert html =~ "My Great Script"
      assert html =~ ~s(id="screenplay-title")
    end

    # -------------------------------------------------------------------------
    # Toolbar
    # -------------------------------------------------------------------------

    test "save_name event updates screenplay name and refreshes tree", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Old Name"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("save_name", %{"name" => "New Name"})

      updated = Storyarn.Screenplays.get_screenplay!(project.id, screenplay.id)
      assert updated.name == "New Name"
    end

    # -------------------------------------------------------------------------
    # Sidebar
    # -------------------------------------------------------------------------

    test "create_screenplay from sidebar creates and navigates", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Current"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("create_screenplay")

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/"
    end

    test "delete_screenplay of another screenplay reloads tree", %{
      conn: conn,
      project: project
    } do
      current = screenplay_fixture(project, %{name: "Current"})
      other = screenplay_fixture(project, %{name: "Other"})

      {:ok, view, html} = live(conn, show_url(project, current))

      assert html =~ "Other"

      view |> render_click("delete_screenplay", %{"id" => to_string(other.id)})

      html = render(view)
      refute html =~ "Other"
      assert html =~ "Screenplay moved to trash"
    end

    test "delete_screenplay of current screenplay redirects to index", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Self Delete"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_screenplay", %{"id" => to_string(screenplay.id)})

      {path, flash} = assert_redirect(view)
      assert path =~ "/screenplays"
      assert flash["info"] =~ "trash"
    end

    # -------------------------------------------------------------------------
    # Authorization
    # -------------------------------------------------------------------------

    test "redirects non-members to /workspaces", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      screenplay = screenplay_fixture(project, %{name: "Private"})

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, show_url(project, screenplay))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    # -------------------------------------------------------------------------
    # Phase 5.2 — Conditional block inline condition builder
    # -------------------------------------------------------------------------

    test "conditional element is embedded in editor JSON as atom node", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "conditional", content: ""})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Conditional is now an atom node in the TipTap editor JSON
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "conditional"
    end

    test "conditional element data appears in editor JSON", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "id" => "r1",
            "sheet" => "mc",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ]
      }

      element_fixture(screenplay, %{
        type: "conditional",
        content: "",
        data: %{"condition" => condition}
      })

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Conditional data is in the TipTap editor JSON
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "conditional"
      assert html =~ "greater_than"
    end

    # -------------------------------------------------------------------------
    # Phase 5.3 — Instruction block inline instruction builder
    # -------------------------------------------------------------------------

    test "instruction element is embedded in editor JSON as atom node", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "instruction", content: ""})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Instruction is now an atom node in the TipTap editor JSON
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "instruction"
    end

    test "instruction element data appears in editor JSON", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      assignments = [
        %{
          "id" => "a1",
          "sheet" => "mc",
          "variable" => "health",
          "operator" => "add",
          "value" => "10",
          "value_type" => "literal",
          "value_sheet" => nil
        }
      ]

      element_fixture(screenplay, %{
        type: "instruction",
        content: "",
        data: %{"assignments" => assignments}
      })

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "instruction"
      assert html =~ "add"
    end

    # -------------------------------------------------------------------------
    # Phase 5.4 — Response block basic choices management
    # -------------------------------------------------------------------------

    test "response element is embedded in editor JSON as atom node", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "response",
        content: "",
        data: %{
          "choices" => [
            %{"id" => "c1", "text" => "Go left"},
            %{"id" => "c2", "text" => "Go right"}
          ]
        }
      })

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "data-content="
      assert html =~ "response"
      assert html =~ "Go left"
    end

    # -------------------------------------------------------------------------
    # Phase 8.2 — Linked pages UI
    # -------------------------------------------------------------------------

    test "linked page data appears in editor JSON for response block", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: nil,
          data: %{
            "choices" => [
              %{"id" => "c1", "text" => "Go left", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      {:ok, child, _updated_el} =
        Storyarn.Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Response is now in TipTap editor JSON; linked page data appears in data-linked-pages
      assert html =~ "data-linked-pages="
      assert html =~ to_string(child.id)
    end

    # -------------------------------------------------------------------------
    # Phase 9.2 — Dual dialogue block
    # -------------------------------------------------------------------------

    test "dual dialogue is embedded in editor JSON as atom node", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "dual_dialogue",
        content: "",
        data: %{
          "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hello."},
          "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi there."}
        }
      })

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "data-content="
      assert html =~ "dualDialogue"
      assert html =~ "ALICE"
    end

    # -------------------------------------------------------------------------
    # Phase 10 — Export toolbar link
    # -------------------------------------------------------------------------

    test "toolbar renders export link with correct path", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project, %{name: "Export Test"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "export/fountain"
      assert html =~ "Export as Fountain"
    end

    # -------------------------------------------------------------------------
    # Phase 10 — Title page interactive NodeView
    # -------------------------------------------------------------------------

    test "title_page element is embedded in editor JSON as atom node", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "title_page", content: ""})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "titlePage"
    end

    test "title_page data appears in editor JSON", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "title_page",
        content: "",
        data: %{
          "title" => "LA TABERNA DEL CUERVO",
          "author" => "Studio Dev"
        }
      })

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "titlePage"
      assert html =~ "LA TABERNA DEL CUERVO"
      assert html =~ "Studio Dev"
    end

    # -------------------------------------------------------------------------
    # Phase 10 — Import Fountain
    # -------------------------------------------------------------------------

    test "import_fountain replaces existing elements with parsed content", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Old content.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      fountain_text = "INT. OFFICE - DAY\n\nJOHN walks in."

      view
      |> render_click("import_fountain", %{"content" => fountain_text})

      html = render(view)
      assert html =~ "imported successfully"

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      types = Enum.map(elements, & &1.type)
      assert "scene_heading" in types
      assert "action" in types
      refute Enum.any?(elements, &(&1.content == "Old content."))
    end

    test "import_fountain with empty content shows error flash", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Keep me.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("import_fountain", %{"content" => ""})

      html = render(view)
      assert html =~ "No content found"

      # Original element preserved
      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      assert hd(elements).content == "Keep me."
    end

    test "viewer cannot import fountain", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Protected.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("import_fountain", %{"content" => "INT. OFFICE - DAY\n\nNew."})

      assert render(view) =~ "permission"
      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert hd(elements).content == "Protected."
    end

    test "import_fountain with title page creates title_page element", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      fountain_text = "Title: My Great Script\nAuthor: Studio Dev\n\nINT. OFFICE - DAY"

      view |> render_click("import_fountain", %{"content" => fountain_text})

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      tp = Enum.find(elements, &(&1.type == "title_page"))
      assert tp
      assert tp.data["title"] == "My Great Script"
      assert tp.data["author"] == "Studio Dev"
    end

    test "import button appears for editors, hidden for viewers", %{
      conn: conn,
      project: project,
      user: user
    } do
      screenplay = screenplay_fixture(project)

      # Editor sees import button
      {:ok, _view, html} = live(conn, show_url(project, screenplay))
      assert html =~ "screenplay-import-btn"
      assert html =~ "Import Fountain"

      # Viewer does not see import button
      owner = user_fixture()
      viewer_project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(viewer_project, user, "viewer")
      viewer_screenplay = screenplay_fixture(viewer_project)

      {:ok, _view, viewer_html} = live(conn, show_url(viewer_project, viewer_screenplay))
      refute viewer_html =~ "screenplay-import-btn"
    end

    # -------------------------------------------------------------------------
    # Phase 5 — Project variables loaded in mount
    # -------------------------------------------------------------------------

    test "mount loads project variables and renders page with sheets present", %{
      conn: conn,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      block_fixture(sheet, %{type: "boolean", config: %{"label" => "Alive"}})

      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk."})

      # Verifies the full integration: Sheets query runs during mount without error
      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "screenplay-page"
      assert html =~ "Walk."
    end
  end

  # -------------------------------------------------------------------------
  # sync_editor_content round-trip
  # -------------------------------------------------------------------------

  describe "sync_editor_content" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "updates existing element type", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "INT. LOBBY", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "element_id" => to_string(el.id),
            "type" => "scene_heading",
            "content" => "INT. LOBBY",
            "data" => %{}
          }
        ]
      })

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert hd(elements).type == "scene_heading"
    end

    test "preserves atom element data", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "id" => "r1",
            "sheet" => "mc",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ]
      }

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{"type" => "conditional", "content" => "", "data" => %{"condition" => condition}}
        ]
      })

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      el = hd(elements)
      assert el.type == "conditional"
      assert el.data["condition"]["logic"] == "all"
      assert length(el.data["condition"]["rules"]) == 1
    end
  end

  # -------------------------------------------------------------------------
  # Phase 9.4 — Read mode
  # -------------------------------------------------------------------------

  describe "read mode" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "toggle_read_mode activates read mode", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk."})

      {:ok, view, html} = live(conn, show_url(project, screenplay))

      refute html =~ "screenplay-read-mode"

      html = view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()

      assert html =~ "screenplay-read-mode"
    end

    test "toggle_read_mode twice deactivates read mode", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()
      html = view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()

      refute html =~ "screenplay-read-mode"
    end

    test "read mode applies sp-read-mode class via CSS (elements hidden client-side)", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk.", position: 0})

      element_fixture(screenplay, %{
        type: "conditional",
        position: 1,
        data: %{"condition" => %{"logic" => "all", "rules" => []}}
      })

      element_fixture(screenplay, %{
        type: "instruction",
        position: 2,
        data: %{"assignments" => []}
      })

      element_fixture(screenplay, %{type: "note", content: "Director note", position: 3})

      {:ok, view, html} = live(conn, show_url(project, screenplay))

      # All elements are in the TipTap editor JSON in edit mode
      assert html =~ "conditional"
      assert html =~ "instruction"
      assert html =~ "Director note"

      html = view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()

      # TipTap editor stays visible — CSS hides interactive blocks
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "screenplay-read-mode"
      # Elements still present in the JSON (hidden by CSS, not removed from DOM)
      assert html =~ "Walk."
    end

    test "read mode preserves visible types in editor", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "scene_heading",
        content: "INT. OFFICE - DAY",
        position: 0
      })

      element_fixture(screenplay, %{type: "action", content: "He enters.", position: 1})
      element_fixture(screenplay, %{type: "character", content: "JOHN", position: 2})
      element_fixture(screenplay, %{type: "dialogue", content: "Hello.", position: 3})
      element_fixture(screenplay, %{type: "transition", content: "CUT TO:", position: 4})

      element_fixture(screenplay, %{
        type: "dual_dialogue",
        position: 5,
        data: %{
          "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hi!"},
          "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hey!"}
        }
      })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      html = view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()

      # Editor remains with all content in JSON — visible types are not hidden by CSS
      assert html =~ ~s(id="screenplay-editor")
      assert html =~ "sceneHeading"
      assert html =~ "INT. OFFICE - DAY"
      assert html =~ "Hello."
      assert html =~ "dualDialogue"
      assert html =~ "ALICE"
    end
  end

  # -------------------------------------------------------------------------
  # Additional show.ex handler coverage
  # -------------------------------------------------------------------------

  describe "tree panel events" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "tree_panel_toggle toggles panel state", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "tree_panel_toggle")

      # View should still be alive
      assert render(view) =~ "screenplay-page"
    end

    test "tree_panel_pin toggles pin state", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "tree_panel_pin")

      assert render(view) =~ "screenplay-page"
    end
  end

  describe "sidebar screenplay management" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "set_pending_delete_screenplay stores id for confirmation", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Main"})
      other = screenplay_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_pending_delete_screenplay", %{"id" => to_string(other.id)})

      # View is alive, pending_delete_id is set (we verify by confirming deletion next)
      assert render(view) =~ "screenplay-page"
    end

    test "confirm_delete_screenplay deletes the pending screenplay", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Main"})
      other = screenplay_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      # Set pending delete
      render_click(view, "set_pending_delete_screenplay", %{"id" => to_string(other.id)})

      # Confirm deletion
      render_click(view, "confirm_delete_screenplay")

      html = render(view)
      assert html =~ "trash" or html =~ "screenplay-page"

      # The other screenplay should be soft-deleted
      deleted = Storyarn.Screenplays.get_screenplay(project.id, other.id)
      assert is_nil(deleted) or (deleted && deleted.deleted_at != nil)
    end

    test "create_child_screenplay creates a child and navigates to it", %{
      conn: conn,
      project: project
    } do
      parent = screenplay_fixture(project, %{name: "Parent Script"})

      {:ok, view, _html} = live(conn, show_url(project, parent))

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "create_child_screenplay", %{
                 "parent-id" => to_string(parent.id)
               })

      assert to =~ "/screenplays/"
    end

    test "move_to_parent moves a screenplay to a new parent", %{
      conn: conn,
      project: project
    } do
      parent = screenplay_fixture(project, %{name: "Parent"})
      child = screenplay_fixture(project, %{name: "Child"})

      {:ok, view, _html} = live(conn, show_url(project, parent))

      render_click(view, "move_to_parent", %{
        "item_id" => to_string(child.id),
        "new_parent_id" => to_string(parent.id),
        "position" => "0"
      })

      # View should still be alive with tree reloaded
      assert render(view) =~ "screenplay-page"
    end
  end
end
