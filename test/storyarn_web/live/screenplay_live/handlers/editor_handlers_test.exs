defmodule StoryarnWeb.ScreenplayLive.Handlers.EditorHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Storyarn.Repo
  alias Storyarn.Screenplays

  describe "EditorHandlers — sync_editor_content" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp show_url(project, screenplay) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
    end

    # -----------------------------------------------------------------------
    # Basic CRUD via sync
    # -----------------------------------------------------------------------

    test "creates new elements when element_id is nil", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{"type" => "scene_heading", "content" => "INT. OFFICE - DAY", "data" => %{}},
          %{"type" => "action", "content" => "A desk.", "data" => %{}}
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 2
      assert Enum.map(elements, & &1.type) == ["scene_heading", "action"]
    end

    test "updates existing element content", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Original.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "element_id" => to_string(el.id),
            "type" => "action",
            "content" => "Updated.",
            "data" => %{}
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      assert hd(elements).content == "Updated."
    end

    test "deletes elements not in the payload", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el1 = element_fixture(screenplay, %{type: "action", content: "Keep.", position: 0})
      _el2 = element_fixture(screenplay, %{type: "action", content: "Delete me.", position: 1})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "element_id" => to_string(el1.id),
            "type" => "action",
            "content" => "Keep.",
            "data" => %{}
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      assert hd(elements).content == "Keep."
    end

    test "handles mixed create, update, and delete", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el1 = element_fixture(screenplay, %{type: "action", content: "Update me.", position: 0})
      _el2 = element_fixture(screenplay, %{type: "action", content: "Delete me.", position: 1})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "element_id" => to_string(el1.id),
            "type" => "action",
            "content" => "Updated.",
            "data" => %{}
          },
          %{"type" => "scene_heading", "content" => "INT. NEW SCENE", "data" => %{}}
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 2
      assert Enum.map(elements, & &1.content) == ["Updated.", "INT. NEW SCENE"]
    end

    test "preserves element order via position", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el1 = element_fixture(screenplay, %{type: "action", content: "First.", position: 0})
      el2 = element_fixture(screenplay, %{type: "action", content: "Second.", position: 1})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      # Send in reversed order
      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "element_id" => to_string(el2.id),
            "type" => "action",
            "content" => "Second.",
            "data" => %{}
          },
          %{
            "element_id" => to_string(el1.id),
            "type" => "action",
            "content" => "First.",
            "data" => %{}
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      assert Enum.map(elements, & &1.content) == ["Second.", "First."]
    end

    # -----------------------------------------------------------------------
    # Data sanitization per type — these hit sanitize_element_data branches
    # -----------------------------------------------------------------------

    test "conditional data is sanitized through sync", %{conn: conn, project: project} do
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

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      el = hd(elements)
      assert el.type == "conditional"
      assert el.data["condition"]["logic"] == "all"
      assert length(el.data["condition"]["rules"]) == 1
    end

    test "instruction data is sanitized through sync", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

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

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "instruction",
            "content" => "",
            "data" => %{"assignments" => assignments}
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      assert el.type == "instruction"
      assert length(el.data["assignments"]) == 1
      assert hd(el.data["assignments"])["operator"] == "set"
    end

    test "response data with choices is sanitized through sync", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "response",
            "content" => "",
            "data" => %{
              "choices" => [
                %{"id" => "c1", "text" => "Go left"},
                %{"id" => "c2", "text" => "Go right"}
              ]
            }
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      assert el.type == "response"
      assert length(el.data["choices"]) == 2
      assert hd(el.data["choices"])["text"] == "Go left"
    end

    test "response choices with condition and instruction are sanitized", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "response",
            "content" => "",
            "data" => %{
              "choices" => [
                %{
                  "id" => "c1",
                  "text" => "Option A",
                  "condition" => %{
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
                  },
                  "instruction" => [
                    %{
                      "id" => "a1",
                      "sheet" => "mc",
                      "variable" => "health",
                      "operator" => "add",
                      "value" => "10"
                    }
                  ]
                }
              ]
            }
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      [choice] = el.data["choices"]
      assert choice["condition"]["logic"] == "all"
      assert length(choice["condition"]["rules"]) == 1
      assert length(choice["instruction"]) == 1
    end

    test "title_page data fields are sanitized through sync", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "title_page",
            "content" => "",
            "data" => %{
              "title" => "My Script",
              "credit" => "Written by",
              "author" => "Studio Dev",
              "draft_date" => "2024-01-01",
              "contact" => "studio@example.com",
              # Invalid field should be stripped
              "evil_field" => "hacked"
            }
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      assert el.type == "title_page"
      assert el.data["title"] == "My Script"
      assert el.data["author"] == "Studio Dev"
      assert el.data["credit"] == "Written by"
      assert el.data["draft_date"] == "2024-01-01"
      assert el.data["contact"] == "studio@example.com"
      refute Map.has_key?(el.data, "evil_field")
    end

    test "dual_dialogue data is sanitized through sync", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "dual_dialogue",
            "content" => "",
            "data" => %{
              "left" => %{
                "character" => "ALICE",
                "parenthetical" => "(softly)",
                "dialogue" => "Hello."
              },
              "right" => %{
                "character" => "BOB",
                "parenthetical" => nil,
                "dialogue" => "Hi there."
              }
            }
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      assert el.type == "dual_dialogue"
      assert el.data["left"]["character"] == "ALICE"
      assert el.data["left"]["dialogue"] == "Hello."
      assert el.data["right"]["character"] == "BOB"
      assert el.data["right"]["dialogue"] == "Hi there."
    end

    test "character data with sheet_id is sanitized through sync", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "character",
            "content" => "JOHN",
            "data" => %{"sheet_id" => 42}
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      assert el.type == "character"
      assert el.data["sheet_id"] == 42
    end

    test "character data with nil sheet_id produces empty data", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "character",
            "content" => "JOHN",
            "data" => %{"sheet_id" => nil}
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      assert el.type == "character"
      assert el.data == %{}
    end

    test "unknown type data produces empty data map", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "type" => "action",
            "content" => "Some action.",
            "data" => %{"random" => "stuff"}
          }
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      el = hd(elements)
      assert el.type == "action"
      # Regular types have data sanitized to empty map
      assert el.data == %{}
    end

    # -----------------------------------------------------------------------
    # Unchanged elements (same content, no update)
    # -----------------------------------------------------------------------

    test "unchanged element content is not marked as changed", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Same.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "element_id" => to_string(el.id),
            "type" => "action",
            "content" => "Same.",
            "data" => %{}
          }
        ]
      })

      # Element should still exist unchanged
      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      assert hd(elements).content == "Same."
    end

    # -----------------------------------------------------------------------
    # Edge cases
    # -----------------------------------------------------------------------

    test "ignores non-list payload gracefully", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Safe.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      # String payload
      view |> render_click("sync_editor_content", %{"elements" => "bad"})

      # nil payload
      view |> render_click("sync_editor_content", %{"elements" => nil})

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      assert hd(elements).id == el.id
    end

    test "element type defaults to action when type is nil", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{"content" => "No type given.", "data" => %{}}
        ]
      })

      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      assert hd(elements).type == "action"
    end

    # -----------------------------------------------------------------------
    # Authorization
    # -----------------------------------------------------------------------

    test "viewer cannot sync_editor_content", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Protected.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("sync_editor_content", %{
        "elements" => [
          %{
            "element_id" => to_string(el.id),
            "type" => "action",
            "content" => "Hacked.",
            "data" => %{}
          }
        ]
      })

      assert render(view) =~ "permission"
      unchanged = Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.content == "Protected."
    end
  end
end
