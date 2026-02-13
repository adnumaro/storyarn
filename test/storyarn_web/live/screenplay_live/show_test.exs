defmodule StoryarnWeb.ScreenplayLive.ShowTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo

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

    test "text elements are embedded in editor JSON with correct types", %{conn: conn, project: project} do
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

    test "flow marker blocks are embedded in editor JSON as atom nodes", %{conn: conn, project: project} do
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
    # Element deletion & type cycling
    # -------------------------------------------------------------------------

    test "delete_element removes element and compacts positions", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el1 = element_fixture(screenplay, %{type: "action", content: "First.", position: 0})
      _el2 = element_fixture(screenplay, %{type: "action", content: "Second.", position: 1})
      _el3 = element_fixture(screenplay, %{type: "action", content: "Third.", position: 2})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el1.id)})

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 2
      assert Enum.map(elements, & &1.position) == [0, 1]
      assert Enum.map(elements, & &1.content) == ["Second.", "Third."]
    end

    test "delete_element of the last element leaves empty list", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Only."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el.id)})

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert elements == []
      # TipTap editor is still present (placeholder text is client-side)
      assert render(view) =~ ~s(id="screenplay-editor")
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

    test "viewer cannot delete elements", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Protected."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el.id)})

      assert render(view) =~ "permission"
      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
    end

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
          %{"id" => "r1", "sheet" => "mc", "variable" => "health", "operator" => "greater_than", "value" => "50"}
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

    test "update_screenplay_condition persists condition to element data", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "conditional", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      condition = %{
        "logic" => "all",
        "rules" => [
          %{"id" => "r1", "sheet" => "mc", "variable" => "health", "operator" => "equals", "value" => "100"}
        ]
      }

      view
      |> render_click("update_screenplay_condition", %{
        "element-id" => to_string(el.id),
        "condition" => condition
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["condition"]["logic"] == "all"
      assert length(updated.data["condition"]["rules"]) == 1
      [rule] = updated.data["condition"]["rules"]
      assert rule["sheet"] == "mc"
      assert rule["variable"] == "health"
    end

    test "update_screenplay_condition with nonexistent element is a no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      _el = element_fixture(screenplay, %{type: "conditional", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_screenplay_condition", %{
        "element-id" => "999999",
        "condition" => %{"logic" => "all", "rules" => []}
      })

      # No crash, page still renders
      assert render(view) =~ "screenplay-page"
    end

    test "viewer cannot update screenplay condition", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "conditional", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_screenplay_condition", %{
        "element-id" => to_string(el.id),
        "condition" => %{
          "logic" => "all",
          "rules" => [
            %{"id" => "r1", "sheet" => "mc", "variable" => "health", "operator" => "equals", "value" => "100"}
          ]
        }
      })

      assert render(view) =~ "permission"
      unchanged = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.data == nil || unchanged.data == %{}
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

    test "update_screenplay_instruction persists assignments to element data", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "instruction", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assignments = [
        %{
          "id" => "a1",
          "sheet" => "mc",
          "variable" => "health",
          "operator" => "set",
          "value" => "100",
          "value_type" => "literal",
          "value_sheet" => nil
        }
      ]

      view
      |> render_click("update_screenplay_instruction", %{
        "element-id" => to_string(el.id),
        "assignments" => assignments
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert length(updated.data["assignments"]) == 1
      [assignment] = updated.data["assignments"]
      assert assignment["sheet"] == "mc"
      assert assignment["variable"] == "health"
      assert assignment["operator"] == "set"
    end

    test "update_screenplay_instruction with nonexistent element is a no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      _el = element_fixture(screenplay, %{type: "instruction", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_screenplay_instruction", %{
        "element-id" => "999999",
        "assignments" => []
      })

      assert render(view) =~ "screenplay-page"
    end

    test "viewer cannot update screenplay instruction", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "instruction", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_screenplay_instruction", %{
        "element-id" => to_string(el.id),
        "assignments" => [
          %{"id" => "a1", "sheet" => "mc", "variable" => "health", "operator" => "set", "value" => "100"}
        ]
      })

      assert render(view) =~ "permission"
      unchanged = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.data == nil || unchanged.data == %{}
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

    test "add_response_choice adds a choice to element data", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "response", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("add_response_choice", %{"element-id" => to_string(el.id)})

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert length(updated.data["choices"]) == 1
      [choice] = updated.data["choices"]
      assert is_binary(choice["id"])
      assert choice["text"] == ""
    end

    test "remove_response_choice removes choice by ID", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{
            "choices" => [
              %{"id" => "c1", "text" => "Keep"},
              %{"id" => "c2", "text" => "Remove"}
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("remove_response_choice", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c2"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert length(updated.data["choices"]) == 1
      [choice] = updated.data["choices"]
      assert choice["text"] == "Keep"
    end

    test "update_response_choice_text updates choice text", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{"choices" => [%{"id" => "c1", "text" => "Old text"}]}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_response_choice_text", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1",
        "value" => "New text"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert choice["text"] == "New text"
    end

    test "viewer cannot add response choice", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "response", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("add_response_choice", %{"element-id" => to_string(el.id)})

      assert render(view) =~ "permission"
      unchanged = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.data == nil || unchanged.data == %{}
    end

    # -------------------------------------------------------------------------
    # Phase 5.5 — Response per-choice condition and instruction
    # -------------------------------------------------------------------------

    test "toggle_choice_condition adds default condition to choice", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{"choices" => [%{"id" => "c1", "text" => "Option A"}]}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("toggle_choice_condition", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert choice["condition"] == %{"logic" => "all", "rules" => []}
    end

    test "toggle_choice_condition removes condition from choice", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{
            "choices" => [
              %{"id" => "c1", "text" => "Option A", "condition" => %{"logic" => "all", "rules" => []}}
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("toggle_choice_condition", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      refute Map.has_key?(choice, "condition")
    end

    test "update_response_choice_condition persists sanitized condition per choice", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{
            "choices" => [
              %{"id" => "c1", "text" => "Option A", "condition" => %{"logic" => "all", "rules" => []}}
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      condition = %{
        "logic" => "any",
        "rules" => [
          %{"id" => "r1", "sheet" => "mc", "variable" => "health", "operator" => "equals", "value" => "50"}
        ]
      }

      view
      |> render_click("update_response_choice_condition", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1",
        "condition" => condition
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert choice["condition"]["logic"] == "any"
      assert length(choice["condition"]["rules"]) == 1
    end

    test "update_response_choice_instruction persists sanitized assignments per choice", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{
            "choices" => [
              %{"id" => "c1", "text" => "Option A", "instruction" => []}
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assignments = [
        %{"id" => "a1", "sheet" => "mc", "variable" => "health", "operator" => "add", "value" => "10"}
      ]

      view
      |> render_click("update_response_choice_instruction", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1",
        "assignments" => assignments
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert length(choice["instruction"]) == 1
      [assignment] = choice["instruction"]
      assert assignment["sheet"] == "mc"
      assert assignment["operator"] == "add"
    end

    test "viewer cannot toggle choice condition", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{"choices" => [%{"id" => "c1", "text" => "Option A"}]}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("toggle_choice_condition", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      assert render(view) =~ "permission"
      unchanged = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = unchanged.data["choices"]
      refute Map.has_key?(choice, "condition")
    end

    # -------------------------------------------------------------------------
    # Phase 6 — Flow sync controls
    # -------------------------------------------------------------------------

    test "mount detects unlinked status and renders Create Flow button", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "Create Flow"
      refute html =~ "sp-sync-linked"
    end

    test "mount detects linked status and renders flow badge", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, screenplay} = Storyarn.Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "sp-sync-linked"
      assert html =~ "Test Flow"
      assert html =~ "To Flow"
      assert html =~ "From Flow"
      refute html =~ "Create Flow"
    end

    test "create_flow_from_screenplay creates flow and syncs", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("create_flow_from_screenplay")

      html = render(view)
      assert html =~ "sp-sync-linked"
      assert html =~ "Flow created and synced"

      updated = Storyarn.Screenplays.get_screenplay!(project.id, screenplay.id)
      assert updated.linked_flow_id != nil
    end

    test "sync_to_flow updates linked flow", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Storyarn.Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_to_flow")

      assert render(view) =~ "synced to flow"
    end

    test "sync_from_flow updates elements from linked flow", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
      element_fixture(screenplay, %{type: "action", content: "Original.", position: 1})

      # Create flow and sync to it
      {:ok, _flow} = Storyarn.Screenplays.FlowSync.sync_to_flow(screenplay)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_from_flow")

      assert render(view) =~ "updated from flow"
    end

    test "sync_from_flow when not linked shows error flash", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Test.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      # Manually trigger the event (button won't be visible but handler exists)
      view |> render_click("sync_from_flow")

      assert render(view) =~ "not linked"
    end

    test "viewer cannot sync from flow", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Storyarn.Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_from_flow")

      assert render(view) =~ "don&#39;t have permission"
    end

    test "unlink_flow clears link and updates status", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Storyarn.Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assert render(view) =~ "sp-sync-linked"

      view |> render_click("unlink_flow")

      html = render(view)
      assert html =~ "Flow unlinked"
      assert html =~ "Create Flow"
      refute html =~ "sp-sync-linked"

      updated = Storyarn.Screenplays.get_screenplay!(project.id, screenplay.id)
      assert is_nil(updated.linked_flow_id)
    end

    # -------------------------------------------------------------------------
    # Phase 8.2 — Linked pages UI
    # -------------------------------------------------------------------------

    test "create_linked_page creates child screenplay and links choice", %{
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
              %{"id" => "c1", "text" => "Go left", "condition" => nil, "instruction" => nil},
              %{"id" => "c2", "text" => "Go right", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      html = render(view)
      assert html =~ "Linked page created"

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      c1 = Enum.find(updated.data["choices"], &(&1["id"] == "c1"))
      assert c1["linked_screenplay_id"]

      children = Storyarn.Screenplays.list_child_screenplays(screenplay.id)
      assert length(children) == 1
      assert hd(children).name == "Go left"
    end

    test "navigate_to_linked_page redirects to child screenplay", %{
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

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("navigate_to_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/#{child.id}"
    end

    test "unlink_choice_screenplay clears link but keeps child page", %{
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

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("unlink_choice_screenplay", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      c1 = Enum.find(updated.data["choices"], &(&1["id"] == "c1"))
      assert is_nil(c1["linked_screenplay_id"])

      # Child page still exists
      assert Storyarn.Screenplays.get_screenplay(project.id, child.id)
    end

    test "generate_all_linked_pages creates pages for all unlinked choices", %{
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
              %{"id" => "c1", "text" => "Go left", "condition" => nil, "instruction" => nil},
              %{"id" => "c2", "text" => "Go right", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("generate_all_linked_pages", %{
        "element-id" => to_string(el.id)
      })

      html = render(view)
      assert html =~ "Linked pages created"

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      choices = updated.data["choices"]
      assert Enum.all?(choices, & &1["linked_screenplay_id"])

      children = Storyarn.Screenplays.list_child_screenplays(screenplay.id)
      assert length(children) == 2
    end

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

    test "viewer cannot create linked pages", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
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

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      assert render(view) =~ "permission"
      children = Storyarn.Screenplays.list_child_screenplays(screenplay.id)
      assert children == []
    end

    test "create_linked_page with empty choice text uses default name", %{
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
              %{"id" => "c1", "text" => "", "condition" => nil, "instruction" => nil}
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      children = Storyarn.Screenplays.list_child_screenplays(screenplay.id)
      assert length(children) == 1
      assert hd(children).name == "Untitled Branch"
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

    test "update_dual_dialogue updates left character", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""},
            "right" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_dual_dialogue", %{
        "element-id" => to_string(el.id),
        "side" => "left",
        "field" => "character",
        "value" => "ALICE"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["character"] == "ALICE"
    end

    test "update_dual_dialogue updates right dialogue", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => ""}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_dual_dialogue", %{
        "element-id" => to_string(el.id),
        "side" => "right",
        "field" => "dialogue",
        "value" => "Hi there."
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["right"]["dialogue"] == "Hi there."
      # Left side unchanged
      assert updated.data["left"]["character"] == "ALICE"
    end

    test "update_dual_dialogue rejects invalid side", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => ""},
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => ""}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_dual_dialogue", %{
        "element-id" => to_string(el.id),
        "side" => "middle",
        "field" => "character",
        "value" => "HACKER"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["character"] == "ALICE"
      assert updated.data["right"]["character"] == "BOB"
    end

    test "toggle_dual_parenthetical turns on parenthetical", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi."}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("toggle_dual_parenthetical", %{
        "element-id" => to_string(el.id),
        "side" => "left"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["parenthetical"] == ""
    end

    test "toggle_dual_parenthetical turns off parenthetical", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "parenthetical" => "(yelling)", "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi."}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("toggle_dual_parenthetical", %{
        "element-id" => to_string(el.id),
        "side" => "left"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert is_nil(updated.data["left"]["parenthetical"])
    end

    test "delete dual_dialogue element removes it", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi."}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el.id)})

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert elements == []
    end

    test "viewer cannot edit dual dialogue", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi."}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_dual_dialogue", %{
        "element-id" => to_string(el.id),
        "side" => "left",
        "field" => "character",
        "value" => "HACKER"
      })

      assert render(view) =~ "permission"
      unchanged = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.data["left"]["character"] == "ALICE"
    end

    test "viewer sees dual dialogue in editor JSON", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "dual_dialogue",
        content: "",
        data: %{
          "left" => %{"character" => "ALICE", "parenthetical" => nil, "dialogue" => "Hello."},
          "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi."}
        }
      })

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "dualDialogue"
      assert html =~ "ALICE"
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

    test "read mode hides conditional elements", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk.", position: 0})

      element_fixture(screenplay, %{
        type: "conditional",
        position: 1,
        data: %{"condition" => %{"logic" => "all", "rules" => []}}
      })

      {:ok, view, html} = live(conn, show_url(project, screenplay))

      # Conditional is in the TipTap editor JSON in edit mode
      assert html =~ "conditional"

      html = view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()

      # In read mode, conditional is hidden (not rendered by element_renderer)
      refute html =~ "sp-conditional"
      assert html =~ "Walk."
    end

    test "read mode hides instruction elements", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk.", position: 0})

      element_fixture(screenplay, %{
        type: "instruction",
        position: 1,
        data: %{"assignments" => []}
      })

      {:ok, view, html} = live(conn, show_url(project, screenplay))

      # Instruction is in the TipTap editor JSON in edit mode
      assert html =~ "instruction"

      html = view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()

      refute html =~ "sp-instruction"
    end

    test "read mode hides note elements", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk.", position: 0})
      element_fixture(screenplay, %{type: "note", content: "Director note", position: 1})

      {:ok, view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "Director note"

      html = view |> element(~s(button[phx-click="toggle_read_mode"])) |> render_click()

      refute html =~ "Director note"
    end

    test "read mode preserves scene_heading, character, dialogue, action, transition, dual_dialogue",
         %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY", position: 0})
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

      assert html =~ "sp-scene_heading"
      assert html =~ "sp-action"
      assert html =~ "sp-character"
      assert html =~ "sp-dialogue"
      assert html =~ "sp-transition"
      assert html =~ "dual_dialogue"
      assert html =~ "INT. OFFICE - DAY"
      assert html =~ "Hello."
    end
  end
end
