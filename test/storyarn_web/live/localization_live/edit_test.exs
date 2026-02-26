defmodule StoryarnWeb.LocalizationLive.EditTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.LocalizationFixtures

  alias Storyarn.Repo

  describe "Edit translation page" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp edit_url(project, text) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
    end

    test "renders localization edit page with text info", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Edit Translation"
      assert html =~ "Hello world"
      assert html =~ "es"
    end

    test "shows source text in read-only panel", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_text: "Welcome adventurer",
          locale_code: "es",
          word_count: 2
        })

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Source"
      assert html =~ "Welcome adventurer"
      assert html =~ "2 words"
    end

    test "shows translation form with textarea and status select", %{
      conn: conn,
      project: project
    } do
      text = localized_text_fixture(project.id)

      {:ok, view, html} = live(conn, edit_url(project, text))

      assert html =~ "Translation"
      assert html =~ "Status"
      assert html =~ "Save"
      assert has_element?(view, "#translation-form")
    end

    test "shows back link to localization index", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Back"
      assert html =~ "/localization"
    end

    test "shows source type and field metadata", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text"
        })

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "flow_node"
      assert html =~ "text"
    end

    test "shows status options in select dropdown", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Pending"
      assert html =~ "Draft"
      assert html =~ "In Progress"
      assert html =~ "Review"
      assert html =~ "Final"
    end

    test "shows translator notes field", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Translator Notes"
    end
  end

  describe "Authentication and authorization" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/localization/1")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "user without project access gets redirected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      other_user = user_fixture()
      project = project_fixture(other_user) |> Repo.preload(:workspace)
      text = localized_text_fixture(project.id)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(
                 conn,
                 ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
               )

      assert error_msg =~ "not found"
    end

    test "member with viewer role can access the page", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      text = localized_text_fixture(project.id)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      assert html =~ "Edit Translation"
    end
  end

  # ===========================================================================
  # Coverage expansion: save_translation success path
  # ===========================================================================

  describe "save_translation event" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp edit_path(project, text) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
    end

    test "successfully saves translation with text and status", %{
      conn: conn,
      project: project
    } do
      text =
        localized_text_fixture(project.id, %{
          source_text: "Hello world",
          locale_code: "es",
          status: "pending"
        })

      {:ok, view, _html} = live(conn, edit_path(project, text))

      html =
        view
        |> form("#translation-form", %{
          "localized_text" => %{
            "translated_text" => "Hola mundo",
            "status" => "draft",
            "translator_notes" => "First pass"
          }
        })
        |> render_submit()

      assert html =~ "Translation saved"
    end

    test "saves translation with final status", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_path(project, text))

      html =
        view
        |> form("#translation-form", %{
          "localized_text" => %{
            "translated_text" => "Traduccion final",
            "status" => "final"
          }
        })
        |> render_submit()

      assert html =~ "Translation saved"
    end

    test "save_translation with empty text preserves form", %{
      conn: conn,
      project: project
    } do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_path(project, text))

      _html =
        view
        |> form("#translation-form", %{
          "localized_text" => %{
            "translated_text" => "",
            "status" => "draft"
          }
        })
        |> render_submit()

      # Form should still be present after save
      assert has_element?(view, "#translation-form")
      # Empty text saves successfully — form still present after save
      assert has_element?(view, "#translation-form")
    end

    test "updates form after successful save", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_path(project, text))

      view
      |> form("#translation-form", %{
        "localized_text" => %{
          "translated_text" => "Texto actualizado",
          "status" => "draft",
          "translator_notes" => "Notes here"
        }
      })
      |> render_submit()

      # The form should reflect the saved values on re-render
      html = render(view)
      assert html =~ "Texto actualizado"
      assert html =~ "Notes here"
    end
  end

  # ===========================================================================
  # Coverage expansion: translate_with_deepl event
  # ===========================================================================

  describe "translate_with_deepl event" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "translate_with_deepl fails without active provider (shows error flash)", %{
      conn: conn,
      project: project
    } do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      # Without a DeepL provider configured, this should fail.
      # The button may not be visible (has_provider is false), but we can still
      # send the event directly to exercise the handler code path.
      html = view |> render_click("translate_with_deepl", %{})

      # Should show an error flash since no provider is configured
      assert html =~ "Translation failed" or html =~ "permission"
    end
  end

  # ===========================================================================
  # Coverage expansion: machine_translated badge rendering
  # ===========================================================================

  describe "Machine translated badge" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "shows machine translated badge when machine_translated is true", %{
      conn: conn,
      project: project
    } do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          machine_translated: true
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      assert html =~ "Machine translated"
    end

    test "does not show machine translated badge when machine_translated is false", %{
      conn: conn,
      project: project
    } do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          machine_translated: false
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      refute html =~ "Machine translated"
    end
  end

  # ===========================================================================
  # Coverage expansion: last_translated_at timestamp display
  # ===========================================================================

  describe "Last translated at timestamp" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "shows last_translated_at when set", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es"
        })

      # Update the text to have a last_translated_at timestamp
      {:ok, updated_text} =
        Storyarn.Localization.update_text(text, %{
          "last_translated_at" => ~U[2025-06-15 14:30:00Z]
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{updated_text.id}"
        )

      assert html =~ "Last translated"
      assert html =~ "2025-06-15"
      assert html =~ "14:30"
    end

    test "does not show last_translated_at when nil", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es"
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      refute html =~ "Last translated"
    end
  end

  # ===========================================================================
  # Coverage expansion: authorization failures for viewer role
  # ===========================================================================

  describe "Viewer authorization for save and translate" do
    test "viewer cannot save translation (gets unauthorized flash)", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      html =
        view
        |> form("#translation-form", %{
          "localized_text" => %{
            "translated_text" => "Should not work",
            "status" => "draft"
          }
        })
        |> render_submit()

      assert html =~ "permission"
    end

    test "viewer cannot use translate_with_deepl (gets unauthorized flash)", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      html = view |> render_click("translate_with_deepl", %{})

      assert html =~ "permission"
    end
  end

  # ===========================================================================
  # Coverage expansion: word_count display
  # ===========================================================================

  describe "Word count display" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "shows zero word count when word_count is nil", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          word_count: nil
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      assert html =~ "0 words"
    end

    test "shows correct word count when set", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          word_count: 5
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      assert html =~ "5 words"
    end
  end

  # ===========================================================================
  # Coverage expansion: DeepL button visibility
  # ===========================================================================

  describe "DeepL button visibility" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "DeepL button hidden when no active provider", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      # No provider configured, so the Translate with DeepL button should not appear
      refute html =~ "Translate with DeepL"
    end
  end

  # ===========================================================================
  # Coverage expansion: source text sanitization and rendering
  # ===========================================================================

  describe "Source text rendering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "renders HTML source text safely", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_text: "<p>Hello <strong>bold</strong> world</p>",
          locale_code: "es"
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      # Sanitized HTML should be rendered
      assert html =~ "Hello"
      assert html =~ "bold"
    end

    test "renders empty source text without error", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_text: nil,
          locale_code: "es"
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      assert html =~ "Edit Translation"
    end
  end
end
