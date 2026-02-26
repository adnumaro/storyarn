defmodule StoryarnWeb.ScreenplayLive.Handlers.ElementHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Screenplays

  describe "ElementHandlers" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp show_url(project, screenplay) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
    end

    # -----------------------------------------------------------------------
    # do_delete_element
    # -----------------------------------------------------------------------

    test "delete_element removes element and reorders", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      _el1 = element_fixture(screenplay, %{type: "action", content: "First.", position: 0})
      el2 = element_fixture(screenplay, %{type: "action", content: "Second.", position: 1})
      _el3 = element_fixture(screenplay, %{type: "action", content: "Third.", position: 2})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el2.id)})

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 2
      assert Enum.map(elements, & &1.content) == ["First.", "Third."]
    end

    test "delete_element of first element focuses nothing (no prev)", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Only.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el.id)})

      elements = Screenplays.list_elements(screenplay.id)
      assert elements == []
    end

    test "delete_element with nonexistent id is a no-op", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      _el = element_fixture(screenplay, %{type: "action", content: "Still here.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => "999999"})

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      assert hd(elements).content == "Still here."
    end

    # -----------------------------------------------------------------------
    # do_update_screenplay_condition
    # -----------------------------------------------------------------------

    test "update_screenplay_condition persists condition data", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "conditional", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "id" => "r1",
            "sheet" => "mc",
            "variable" => "health",
            "operator" => "equals",
            "value" => "100"
          }
        ]
      }

      view
      |> render_click("update_screenplay_condition", %{
        "element-id" => to_string(el.id),
        "condition" => condition
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["condition"]["logic"] == "all"
      assert length(updated.data["condition"]["rules"]) == 1
    end

    test "update_screenplay_condition with nonexistent element is no-op", %{
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

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_update_screenplay_instruction
    # -----------------------------------------------------------------------

    test "update_screenplay_instruction persists assignments", %{
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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert length(updated.data["assignments"]) == 1
    end

    test "update_screenplay_instruction with nonexistent element is no-op", %{
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

    # -----------------------------------------------------------------------
    # do_add_response_choice
    # -----------------------------------------------------------------------

    test "add_response_choice adds a choice to element data", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "response", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("add_response_choice", %{"element-id" => to_string(el.id)})

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert length(updated.data["choices"]) == 1
      [choice] = updated.data["choices"]
      assert is_binary(choice["id"])
      assert choice["text"] == ""
    end

    test "add_response_choice appends to existing choices", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{"choices" => [%{"id" => "c1", "text" => "Existing"}]}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("add_response_choice", %{"element-id" => to_string(el.id)})

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert length(updated.data["choices"]) == 2
      assert hd(updated.data["choices"])["text"] == "Existing"
    end

    test "add_response_choice with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      _el = element_fixture(screenplay, %{type: "response", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("add_response_choice", %{"element-id" => "999999"})

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_remove_response_choice
    # -----------------------------------------------------------------------

    test "remove_response_choice removes choice by ID", %{conn: conn, project: project} do
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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert length(updated.data["choices"]) == 1
      [choice] = updated.data["choices"]
      assert choice["text"] == "Keep"
    end

    test "remove_response_choice with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{"choices" => [%{"id" => "c1", "text" => "Stay"}]}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("remove_response_choice", %{
        "element-id" => "999999",
        "choice-id" => "c1"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_update_response_choice_text
    # -----------------------------------------------------------------------

    test "update_response_choice_text updates choice text", %{conn: conn, project: project} do
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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert choice["text"] == "New text"
    end

    test "update_response_choice_text with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
        element_fixture(screenplay, %{
          type: "response",
          content: "",
          data: %{"choices" => [%{"id" => "c1", "text" => "Safe"}]}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_response_choice_text", %{
        "element-id" => "999999",
        "choice-id" => "c1",
        "value" => "Hacked"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_toggle_choice_condition
    # -----------------------------------------------------------------------

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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
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
              %{
                "id" => "c1",
                "text" => "Option A",
                "condition" => %{"logic" => "all", "rules" => []}
              }
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("toggle_choice_condition", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      refute Map.has_key?(choice, "condition")
    end

    # -----------------------------------------------------------------------
    # do_toggle_choice_instruction
    # -----------------------------------------------------------------------

    test "toggle_choice_instruction adds instruction to choice", %{
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
      |> render_click("toggle_choice_instruction", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert choice["instruction"] == []
    end

    test "toggle_choice_instruction removes instruction from choice", %{
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

      view
      |> render_click("toggle_choice_instruction", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      refute Map.has_key?(choice, "instruction")
    end

    # -----------------------------------------------------------------------
    # do_set_character_sheet
    # -----------------------------------------------------------------------

    test "set_character_sheet updates element with sheet reference", %{
      conn: conn,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "character",
          content: "ALICE",
          data: %{}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_character_sheet", %{
        "id" => to_string(el.id),
        "sheet_id" => to_string(sheet.id)
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["sheet_id"] == sheet.id
      assert updated.content == "JAIME"
    end

    test "set_character_sheet with nil sheet_id clears the reference", %{
      conn: conn,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "character",
          content: "JAIME",
          data: %{"sheet_id" => sheet.id}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_character_sheet", %{
        "id" => to_string(el.id),
        "sheet_id" => ""
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert is_nil(updated.data["sheet_id"])
    end

    test "set_character_sheet with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      _el = element_fixture(screenplay, %{type: "character", content: "ALICE"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_character_sheet", %{
        "id" => "999999",
        "sheet_id" => "1"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_update_dual_dialogue
    # -----------------------------------------------------------------------

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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["character"] == "ALICE"
    end

    test "update_dual_dialogue updates right dialogue", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "dialogue" => ""}
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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["right"]["dialogue"] == "Hi there."
      assert updated.data["left"]["character"] == "ALICE"
    end

    test "update_dual_dialogue updates parenthetical field", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "parenthetical" => "", "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi."}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_dual_dialogue", %{
        "element-id" => to_string(el.id),
        "side" => "left",
        "field" => "parenthetical",
        "value" => "(softly)"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["parenthetical"] == "(softly)"
    end

    test "update_dual_dialogue rejects invalid side", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "dialogue" => ""},
            "right" => %{"character" => "BOB", "dialogue" => ""}
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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["character"] == "ALICE"
      assert updated.data["right"]["character"] == "BOB"
    end

    test "update_dual_dialogue rejects invalid field", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "dialogue" => ""},
            "right" => %{"character" => "BOB", "dialogue" => ""}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_dual_dialogue", %{
        "element-id" => to_string(el.id),
        "side" => "left",
        "field" => "evil_field",
        "value" => "hack"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["character"] == "ALICE"
      refute Map.has_key?(updated.data["left"], "evil_field")
    end

    test "update_dual_dialogue with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "dialogue" => ""},
            "right" => %{"character" => "BOB", "dialogue" => ""}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_dual_dialogue", %{
        "element-id" => "999999",
        "side" => "left",
        "field" => "character",
        "value" => "GHOST"
      })

      unchanged = Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.data["left"]["character"] == "ALICE"
    end

    # -----------------------------------------------------------------------
    # do_toggle_dual_parenthetical
    # -----------------------------------------------------------------------

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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["left"]["parenthetical"] == ""
    end

    test "toggle_dual_parenthetical turns off parenthetical", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{
              "character" => "ALICE",
              "parenthetical" => "(yelling)",
              "dialogue" => "Hello."
            },
            "right" => %{"character" => "BOB", "parenthetical" => nil, "dialogue" => "Hi."}
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("toggle_dual_parenthetical", %{
        "element-id" => to_string(el.id),
        "side" => "left"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert is_nil(updated.data["left"]["parenthetical"])
    end

    test "toggle_dual_parenthetical with right side", %{conn: conn, project: project} do
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
        "side" => "right"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["right"]["parenthetical"] == ""
      # Left side unchanged
      assert is_nil(updated.data["left"]["parenthetical"])
    end

    test "toggle_dual_parenthetical with invalid side is no-op", %{
      conn: conn,
      project: project
    } do
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
        "side" => "center"
      })

      unchanged = Screenplays.list_elements(screenplay.id) |> hd()
      assert is_nil(unchanged.data["left"]["parenthetical"])
      assert is_nil(unchanged.data["right"]["parenthetical"])
    end

    test "toggle_dual_parenthetical with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
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
        "element-id" => "999999",
        "side" => "left"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_update_title_page
    # -----------------------------------------------------------------------

    test "update_title_page persists field to element data", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "title_page", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_title_page", %{
        "element-id" => to_string(el.id),
        "field" => "title",
        "value" => "MY GREAT SCRIPT"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["title"] == "MY GREAT SCRIPT"
    end

    test "update_title_page updates multiple fields independently", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "title_page",
          content: "",
          data: %{"title" => "Original"}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_title_page", %{
        "element-id" => to_string(el.id),
        "field" => "author",
        "value" => "Studio Dev"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["author"] == "Studio Dev"
      assert updated.data["title"] == "Original"
    end

    test "update_title_page with all valid fields", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "title_page", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      for {field, value} <- [
            {"title", "My Title"},
            {"credit", "Written by"},
            {"author", "Author Name"},
            {"draft_date", "2024-01-01"},
            {"contact", "info@example.com"}
          ] do
        view
        |> render_click("update_title_page", %{
          "element-id" => to_string(el.id),
          "field" => field,
          "value" => value
        })
      end

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.data["title"] == "My Title"
      assert updated.data["credit"] == "Written by"
      assert updated.data["author"] == "Author Name"
      assert updated.data["draft_date"] == "2024-01-01"
      assert updated.data["contact"] == "info@example.com"
    end

    test "update_title_page rejects invalid field name", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "title_page",
          content: "",
          data: %{"title" => "Original"}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_title_page", %{
        "element-id" => to_string(el.id),
        "field" => "evil_field",
        "value" => "hacked"
      })

      unchanged = Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.data["title"] == "Original"
      refute Map.has_key?(unchanged.data, "evil_field")
    end

    test "update_title_page with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      _el = element_fixture(screenplay, %{type: "title_page", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_title_page", %{
        "element-id" => "999999",
        "field" => "title",
        "value" => "Ghost"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # update_choice_field (shared through various events)
    # -----------------------------------------------------------------------

    test "update_response_choice_condition persists condition per choice", %{
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
              %{
                "id" => "c1",
                "text" => "Option A",
                "condition" => %{"logic" => "all", "rules" => []}
              }
            ]
          }
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      condition = %{
        "logic" => "any",
        "rules" => [
          %{
            "id" => "r1",
            "sheet" => "mc",
            "variable" => "health",
            "operator" => "equals",
            "value" => "50"
          }
        ]
      }

      view
      |> render_click("update_response_choice_condition", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1",
        "condition" => condition
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert choice["condition"]["logic"] == "any"
    end

    test "update_response_choice_instruction persists assignments per choice", %{
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
        %{
          "id" => "a1",
          "sheet" => "mc",
          "variable" => "health",
          "operator" => "add",
          "value" => "10"
        }
      ]

      view
      |> render_click("update_response_choice_instruction", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1",
        "assignments" => assignments
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      [choice] = updated.data["choices"]
      assert length(choice["instruction"]) == 1
    end

    # -----------------------------------------------------------------------
    # handle_search_character_sheets and handle_mention_suggestions
    # -----------------------------------------------------------------------

    test "search_character_sheets returns results", %{conn: conn, project: project} do
      _sheet = sheet_fixture(project, %{name: "Protagonist", shortcut: "mc.protagonist"})
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "search_character_sheets", %{"query" => "Protagonist"})

      assert render(view) =~ "screenplay-page"
    end

    test "mention_suggestions returns results", %{conn: conn, project: project} do
      _sheet = sheet_fixture(project, %{name: "Companion", shortcut: "mc.companion"})
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "mention_suggestions", %{"query" => "Comp"})

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # handle_navigate_to_sheet
    # -----------------------------------------------------------------------

    test "navigate_to_sheet redirects to sheet page", %{conn: conn, project: project} do
      sheet = sheet_fixture(project, %{name: "NavTarget", shortcut: "mc.navtarget"})
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "navigate_to_sheet", %{
                 "sheet_id" => to_string(sheet.id)
               })

      assert to =~ "/sheets/#{sheet.id}"
    end

    test "navigate_to_sheet with nonexistent sheet is no-op", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "navigate_to_sheet", %{"sheet_id" => "999999"})

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # Authorization
    # -----------------------------------------------------------------------

    test "viewer cannot delete elements", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Protected."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el.id)})

      assert render(view) =~ "permission"
      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
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
    end

    test "viewer cannot update dual dialogue", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "dual_dialogue",
          content: "",
          data: %{
            "left" => %{"character" => "ALICE", "dialogue" => "Hello."},
            "right" => %{"character" => "BOB", "dialogue" => "Hi."}
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
      unchanged = Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.data["left"]["character"] == "ALICE"
    end

    test "viewer cannot update title page", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "title_page", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_title_page", %{
        "element-id" => to_string(el.id),
        "field" => "title",
        "value" => "Hacked"
      })

      assert render(view) =~ "permission"
    end

    test "viewer cannot set character sheet", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "character", content: "ALICE"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_character_sheet", %{
        "id" => to_string(el.id),
        "sheet_id" => "1"
      })

      assert render(view) =~ "permission"
    end
  end
end
