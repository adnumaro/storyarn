defmodule StoryarnWeb.ScreenplayLive.Handlers.LinkedPageHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Storyarn.Repo
  alias Storyarn.Screenplays

  describe "LinkedPageHandlers" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp show_url(project, screenplay) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
    end

    # -----------------------------------------------------------------------
    # do_create_linked_page
    # -----------------------------------------------------------------------

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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      c1 = Enum.find(updated.data["choices"], &(&1["id"] == "c1"))
      assert c1["linked_screenplay_id"]

      children = Screenplays.list_child_screenplays(screenplay.id)
      assert length(children) == 1
      assert hd(children).name == "Go left"
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

      children = Screenplays.list_child_screenplays(screenplay.id)
      assert length(children) == 1
      assert hd(children).name == "Untitled Branch"
    end

    test "create_linked_page for already linked choice shows error", %{
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

      # Create the linked page first
      {:ok, _child, _updated_el} =
        Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      html = render(view)
      assert html =~ "already" or html =~ "linked page"
    end

    test "create_linked_page with nonexistent choice shows error", %{
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

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "nonexistent"
      })

      html = render(view)
      assert html =~ "not found" or html =~ "Could not"
    end

    test "create_linked_page with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
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
        "element-id" => "999999",
        "choice-id" => "c1"
      })

      # No child created
      children = Screenplays.list_child_screenplays(screenplay.id)
      assert children == []
    end

    # -----------------------------------------------------------------------
    # do_navigate_to_linked_page
    # -----------------------------------------------------------------------

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
        Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("navigate_to_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/#{child.id}"
    end

    test "navigate_to_linked_page with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
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
      |> render_click("navigate_to_linked_page", %{
        "element-id" => "999999",
        "choice-id" => "c1"
      })

      # Should not redirect
      assert render(view) =~ "screenplay-page"
    end

    test "navigate_to_linked_page with no linked_screenplay_id is no-op", %{
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

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("navigate_to_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      # Should not redirect (choice has no linked page)
      assert render(view) =~ "screenplay-page"
    end

    test "navigate_to_linked_page with nonexistent choice is no-op", %{
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

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("navigate_to_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "nonexistent"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_unlink_choice_screenplay
    # -----------------------------------------------------------------------

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
        Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("unlink_choice_screenplay", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      c1 = Enum.find(updated.data["choices"], &(&1["id"] == "c1"))
      assert is_nil(c1["linked_screenplay_id"])

      # Child page still exists
      assert Screenplays.get_screenplay(project.id, child.id)
    end

    test "unlink_choice_screenplay with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
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
      |> render_click("unlink_choice_screenplay", %{
        "element-id" => "999999",
        "choice-id" => "c1"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # do_generate_all_linked_pages
    # -----------------------------------------------------------------------

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

      updated = Screenplays.list_elements(screenplay.id) |> hd()
      choices = updated.data["choices"]
      assert Enum.all?(choices, & &1["linked_screenplay_id"])

      children = Screenplays.list_child_screenplays(screenplay.id)
      assert length(children) == 2
    end

    test "generate_all_linked_pages skips already linked choices", %{
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

      # Link only c1
      {:ok, _child, _updated_el} =
        Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("generate_all_linked_pages", %{
        "element-id" => to_string(el.id)
      })

      children = Screenplays.list_child_screenplays(screenplay.id)
      # Should have 2 children: one from manual link, one from generate
      assert length(children) == 2
    end

    test "generate_all_linked_pages with all choices already linked succeeds", %{
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

      # Link the only choice
      {:ok, _child, _updated_el} =
        Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("generate_all_linked_pages", %{
        "element-id" => to_string(el.id)
      })

      # Should succeed with "Linked pages created" (even if none were created)
      html = render(view)
      assert html =~ "Linked pages created"

      # No additional children
      children = Screenplays.list_child_screenplays(screenplay.id)
      assert length(children) == 1
    end

    test "generate_all_linked_pages with no choices creates no children", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el =
        element_fixture(screenplay, %{
          type: "response",
          content: nil,
          data: %{"choices" => []}
        })

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("generate_all_linked_pages", %{
        "element-id" => to_string(el.id)
      })

      children = Screenplays.list_child_screenplays(screenplay.id)
      assert children == []
    end

    test "generate_all_linked_pages with nonexistent element is no-op", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      _el =
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
      |> render_click("generate_all_linked_pages", %{
        "element-id" => "999999"
      })

      children = Screenplays.list_child_screenplays(screenplay.id)
      assert children == []
    end

    test "generate_all_linked_pages with nil data creates no children", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      el = element_fixture(screenplay, %{type: "response", content: nil})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("generate_all_linked_pages", %{
        "element-id" => to_string(el.id)
      })

      children = Screenplays.list_child_screenplays(screenplay.id)
      assert children == []
    end

    # -----------------------------------------------------------------------
    # Authorization
    # -----------------------------------------------------------------------

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
      children = Screenplays.list_child_screenplays(screenplay.id)
      assert children == []
    end

    test "viewer cannot unlink choice screenplay", %{conn: conn, user: user} do
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

      {:ok, _child, _updated_el} =
        Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("unlink_choice_screenplay", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      assert render(view) =~ "permission"

      # Link should still be present
      updated = Screenplays.list_elements(screenplay.id) |> hd()
      c1 = Enum.find(updated.data["choices"], &(&1["id"] == "c1"))
      assert c1["linked_screenplay_id"]
    end

    test "viewer cannot generate all linked pages", %{conn: conn, user: user} do
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

      assert render(view) =~ "permission"
      children = Screenplays.list_child_screenplays(screenplay.id)
      assert children == []
    end

    # -----------------------------------------------------------------------
    # navigate_to_linked_page does NOT require edit auth (read-only)
    # -----------------------------------------------------------------------

    test "viewer can navigate to linked page", %{conn: conn, user: user} do
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

      {:ok, child, _updated_el} =
        Screenplays.create_linked_page(screenplay, el, "c1")

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("navigate_to_linked_page", %{
        "element-id" => to_string(el.id),
        "choice-id" => "c1"
      })

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/#{child.id}"
    end
  end
end
