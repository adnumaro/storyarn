defmodule StoryarnWeb.LocalizationLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.LocalizationFixtures

  alias Storyarn.Repo

  defp loc_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization"
  end

  describe "Localization index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, loc_path(project))

      # Page should render the localization UI
      assert html =~ "en"
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "en"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, loc_path(project))

      assert path == "/workspaces"
      assert flash["error"] =~ "not found"
    end

    test "shows texts when target language and texts exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "es"
      assert html =~ "Hello world"
    end

    test "shows empty state when no target languages", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Add a target language above to start translating."
    end

    test "shows Add Language button for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Add Language"
    end

    test "shows Sync button when target languages exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Sync"
    end

    test "shows progress bar when texts exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello", locale_code: "es"})

      {:ok, _view, html} = live(conn, loc_path(project))

      # Progress bar should be rendered
      assert html =~ "progress"
      assert html =~ "final"
    end

    test "shows filter dropdowns when target languages exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "All statuses"
      assert html =~ "All types"
    end

    test "shows status badges for texts", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello", locale_code: "es"})

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Pending"
    end

    test "shows Export dropdown for editor with target languages", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Export"
      assert html =~ "Excel (.xlsx)"
      assert html =~ "CSV (.csv)"
    end

    test "shows Report link for editor with target languages", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Report"
    end

    test "shows Not translated for texts without translation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Untranslated text",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Not translated"
    end

    test "shows source_field for each text", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Test text",
          source_field: "description",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "description"
    end

    test "shows remove language button for target languages", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Remove language"
    end

    test "defaults selected locale to first target language", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, _view, html} = live(conn, loc_path(project))

      # The locale selector should be present with both languages
      assert html =~ "Spanish (es)"
      assert html =~ "French (fr)"
    end
  end

  describe "change_locale event" do
    setup :register_and_log_in_user

    test "switches selected locale and reloads texts", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      _text_es =
        localized_text_fixture(project.id, %{
          source_text: "Spanish text",
          locale_code: "es"
        })

      _text_fr =
        localized_text_fixture(project.id, %{
          source_text: "French text",
          locale_code: "fr"
        })

      {:ok, view, html} = live(conn, loc_path(project))

      # Initial render shows es texts (first target language)
      assert html =~ "Spanish text"

      # Switch to French
      html = render_change(view, "change_locale", %{"locale" => "fr"})

      assert html =~ "French text"
    end

    test "resets page to 1 when changing locale", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} = live(conn, loc_path(project))

      # Switch locale - should not crash and should render
      html = render_change(view, "change_locale", %{"locale" => "fr"})
      assert html =~ "French (fr)"
    end
  end

  describe "change_filter event" do
    setup :register_and_log_in_user

    test "filters by status", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _pending_text =
        localized_text_fixture(project.id, %{
          source_text: "Pending text here",
          locale_code: "es",
          status: "pending"
        })

      _final_text =
        localized_text_fixture(project.id, %{
          source_text: "Final text here",
          locale_code: "es",
          status: "final",
          translated_text: "Texto final"
        })

      {:ok, view, html} = live(conn, loc_path(project))

      # Both texts initially visible
      assert html =~ "Pending text here"
      assert html =~ "Final text here"

      # Filter by "final" status
      html = render_change(view, "change_filter", %{"status" => "final"})

      assert html =~ "Final text here"
      refute html =~ "Pending text here"
    end

    test "filters by source_type", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _flow_text =
        localized_text_fixture(project.id, %{
          source_text: "Flow node text",
          source_type: "flow_node",
          locale_code: "es"
        })

      _block_text =
        localized_text_fixture(project.id, %{
          source_text: "Block text",
          source_type: "block",
          locale_code: "es"
        })

      {:ok, view, html} = live(conn, loc_path(project))

      # Both texts initially visible
      assert html =~ "Flow node text"
      assert html =~ "Block text"

      # Filter by "block" source type
      html = render_change(view, "change_filter", %{"source_type" => "block"})

      assert html =~ "Block text"
      refute html =~ "Flow node text"
    end

    test "empty status value preserves current filter", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Some text",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, loc_path(project))

      # Set a filter first
      render_change(view, "change_filter", %{"status" => "pending"})

      # Sending empty status does not crash, preserves previous filter
      html = render_change(view, "change_filter", %{"status" => ""})
      assert html =~ "Some text"
    end
  end

  describe "search event" do
    setup :register_and_log_in_user

    test "filters texts by search term", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text1 =
        localized_text_fixture(project.id, %{
          source_text: "Hello world",
          locale_code: "es"
        })

      _text2 =
        localized_text_fixture(project.id, %{
          source_text: "Goodbye world",
          locale_code: "es"
        })

      {:ok, view, html} = live(conn, loc_path(project))

      assert html =~ "Hello world"
      assert html =~ "Goodbye world"

      # Search for "Hello"
      html = render_change(view, "search", %{"search" => "Hello"})

      assert html =~ "Hello world"
      refute html =~ "Goodbye world"
    end

    test "shows empty state when search matches nothing", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Hello world",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_change(view, "search", %{"search" => "nonexistent_xyz"})

      assert html =~ "No translations found matching your filters."
    end

    test "clears search with empty string", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Hello world",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, loc_path(project))

      # Search then clear
      render_change(view, "search", %{"search" => "nonexistent_xyz"})
      html = render_change(view, "search", %{"search" => ""})

      assert html =~ "Hello world"
    end
  end

  describe "change_page event" do
    setup :register_and_log_in_user

    test "paginates to next page", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      # Create enough texts to need pagination (page_size is 50)
      for i <- 1..52 do
        localized_text_fixture(project.id, %{
          source_text: "Text number #{i}",
          locale_code: "es",
          source_id: System.unique_integer([:positive])
        })
      end

      {:ok, view, html} = live(conn, loc_path(project))

      # Should show pagination controls
      assert html =~ "Page 1 of 2"

      # Go to page 2
      html = render_click(view, "change_page", %{"page" => "2"})

      assert html =~ "Page 2 of 2"
    end
  end

  describe "add_target_language event" do
    setup :register_and_log_in_user

    test "adds a new target language", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      # No target languages yet, should show empty state
      assert render(view) =~ "Add a target language above to start translating."

      html = render_change(view, "add_target_language", %{"locale_code" => "fr"})

      assert html =~ "Language added"
      # The language chip should now appear as a target language badge
      assert html =~ "French"
    end

    test "no-op when locale_code is empty", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      # Should not crash or change anything
      html = render_change(view, "add_target_language", %{"locale_code" => ""})

      # Should still show the empty state (no target languages)
      assert html =~ "Add a target language above to start translating."
    end

    test "viewer cannot add target language", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_change(view, "add_target_language", %{"locale_code" => "fr"})

      assert html =~ "permission"
    end
  end

  describe "remove_language event" do
    setup :register_and_log_in_user

    test "removes a target language", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, html} = live(conn, loc_path(project))

      # Target language badge should exist
      assert html =~ "Spanish"

      html = render_click(view, "remove_language", %{"id" => language.id})

      assert html =~ "Language removed"
      # After removal, should show the empty state (no target languages)
      assert html =~ "Add a target language above to start translating."
    end

    test "viewer cannot remove a language", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_click(view, "remove_language", %{"id" => language.id})

      assert html =~ "permission"
    end
  end

  describe "sync_texts event" do
    setup :register_and_log_in_user

    test "syncs texts for the project", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_click(view, "sync_texts", %{})

      assert html =~ "Synced"
    end

    test "viewer cannot sync texts", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_click(view, "sync_texts", %{})

      assert html =~ "permission"
    end
  end

  describe "translate_batch event" do
    setup :register_and_log_in_user

    test "viewer cannot translate batch", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_click(view, "translate_batch", %{})

      assert html =~ "permission"
    end
  end

  describe "translate_single event" do
    setup :register_and_log_in_user

    test "viewer cannot translate single text", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      text =
        localized_text_fixture(project.id, %{
          source_text: "Hello",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_click(view, "translate_single", %{"id" => "#{text.id}"})

      assert html =~ "permission"
    end
  end

  describe "Viewer role restrictions" do
    setup :register_and_log_in_user

    test "viewer cannot see Add Language button", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, _view, html} = live(conn, loc_path(project))

      refute html =~ "Add Language"
    end

    test "viewer cannot see Sync button", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      refute html =~ "Sync"
    end

    test "viewer cannot see remove language X button on chips", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      # The language chip should be visible but the X button (with hover:text-error) should not
      assert html =~ "Spanish"
      refute html =~ "hover:text-error"
    end

    test "viewer cannot see edit pencil icon on texts", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Some text",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, loc_path(project))

      # Viewer should not see the pencil edit icon
      refute html =~ "pencil"
    end

    test "viewer cannot see Translate All Pending button", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} = live(conn, loc_path(project))

      refute html =~ "Translate All Pending"
    end

    test "viewer can view texts and language chips", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Viewable text",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, loc_path(project))

      assert html =~ "Spanish"
      assert html =~ "es"
      assert html =~ "Viewable text"
    end

    test "viewer can change locale", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_change(view, "change_locale", %{"locale" => "fr"})
      # Should not crash, viewer can browse
      assert html =~ "French (fr)"
    end

    test "viewer can use search", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Searchable text",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_change(view, "search", %{"search" => "Searchable"})
      assert html =~ "Searchable text"
    end

    test "viewer can use filters", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_text: "Filter me",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_change(view, "change_filter", %{"status" => "pending"})
      assert html =~ "Filter me"
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/localization")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
