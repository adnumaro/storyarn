defmodule StoryarnWeb.LocalizationLive.ReportTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.LocalizationFixtures

  alias Storyarn.Repo

  describe "Localization report page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "Localization Report"
      assert html =~ "Progress by Language"
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "Localization Report"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "not found"
    end

    test "shows empty state when no target languages", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "No target languages configured"
    end

    test "shows language progress when target languages exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "es"
      assert html =~ "Spanish"
    end

    test "shows back link to localization index", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "Back to Translations"
    end
  end

  describe "Locale selection" do
    setup :register_and_log_in_user

    test "change_locale event reloads report data", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # Change locale to French
      html = view |> render_change("change_locale", %{"locale" => "fr"})

      # Page still renders without crash
      assert html =~ "Localization Report"
    end

    test "selected_locale defaults to first target language", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # The select should have es selected (first language)
      assert html =~ "es"
      assert html =~ "Spanish"
    end
  end

  describe "Report data sections" do
    setup :register_and_log_in_user

    test "shows VO progress section when locale selected", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "Voice-Over Progress"
      assert html =~ "None"
      assert html =~ "Needed"
      assert html =~ "Recorded"
      assert html =~ "Approved"
    end

    test "language progress shows percentage and counts", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # Should show progress bar area with the language
      assert html =~ "es"
      assert html =~ "Spanish"
      assert html =~ "%"
    end

    test "handles project with no localized texts", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # Should still render VO progress with zero values
      assert html =~ "Voice-Over Progress"
    end
  end

  describe "Viewer role" do
    setup :register_and_log_in_user

    test "viewer can access report page", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "Localization Report"
    end

    test "viewer can change locale", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      html = view |> render_change("change_locale", %{"locale" => "fr"})
      assert html =~ "Localization Report"
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/localization/report")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  # ===========================================================================
  # Coverage expansion: type_icon/1 and type_label/1 (via content breakdown)
  # ===========================================================================

  describe "Content breakdown with various source types" do
    setup :register_and_log_in_user

    defp report_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
    end

    test "renders flow_node type icon and label in content breakdown", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, report_url(project))

      # flow_node type_icon returns "message-square", type_label returns "Nodes"
      assert html =~ "Nodes"
      assert html =~ "message-square"
    end

    test "renders block type icon and label in content breakdown", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "block",
          source_field: "label",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, report_url(project))

      assert html =~ "Blocks"
    end

    test "renders sheet type icon and label in content breakdown", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "sheet",
          source_field: "name",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, report_url(project))

      assert html =~ "Sheets"
      assert html =~ "file-text"
    end

    test "renders flow type icon and label in content breakdown", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow",
          source_field: "name",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, report_url(project))

      assert html =~ "Flows"
      assert html =~ "git-branch"
    end

    test "renders screenplay type icon and label in content breakdown", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "screenplay",
          source_field: "name",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, report_url(project))

      assert html =~ "Screenplays"
      assert html =~ "clapperboard"
    end

    test "renders multiple source types in content breakdown", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text1 =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text",
          locale_code: "es"
        })

      _text2 =
        localized_text_fixture(project.id, %{
          source_type: "block",
          source_field: "label",
          locale_code: "es"
        })

      {:ok, _view, html} = live(conn, report_url(project))

      # Both types should appear in the content breakdown
      assert html =~ "Content Breakdown"
      assert html =~ "Nodes"
      assert html =~ "Blocks"
    end
  end

  # ===========================================================================
  # Coverage expansion: speaker_stats hidden when empty, type_counts hidden when empty
  # ===========================================================================

  describe "Conditional section visibility" do
    setup :register_and_log_in_user

    test "speaker_stats section is hidden when locale is selected but no speaker stats", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      # No localized texts with speakers, so speaker_stats will be []
      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # The "Word Counts by Speaker" section requires @selected_locale && @speaker_stats != []
      # With no texts, speaker_stats is [], so it should not appear
      refute html =~ "Word Counts by Speaker"

      # But VO progress should still appear (requires @selected_locale only)
      assert html =~ "Voice-Over Progress"
    end

    test "content breakdown section is hidden when type_counts is empty", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      # No localized texts at all, so type_counts will be %{}
      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # Content Breakdown requires @selected_locale && @type_counts != %{}
      refute html =~ "Content Breakdown"
    end

    test "content breakdown section appears when there are localized texts", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text",
          locale_code: "es"
        })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      assert html =~ "Content Breakdown"
    end
  end

  # ===========================================================================
  # Coverage expansion: nil locale path (no target languages)
  # ===========================================================================

  describe "Nil locale path" do
    setup :register_and_log_in_user

    test "selected_locale is nil when no target languages exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      # No languages created — selected_locale should be nil
      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # With nil locale, conditional sections should not render
      refute html =~ "Voice-Over Progress"
      refute html =~ "Word Counts by Speaker"
      refute html =~ "Content Breakdown"

      # But the empty state for languages should appear
      assert html =~ "No target languages configured"
    end

    test "VO progress section hidden when no locale selected", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      refute html =~ "None"
      refute html =~ "Needed"
      refute html =~ "Recorded"
      refute html =~ "Approved"
    end
  end

  # ===========================================================================
  # Coverage expansion: locale change between multiple languages
  # ===========================================================================

  describe "Locale switching with content" do
    setup :register_and_log_in_user

    test "switching locale reloads data for the new locale", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      # Create texts for Spanish locale
      _text_es =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text",
          locale_code: "es"
        })

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/report"
        )

      # Initially shows Spanish data with content breakdown
      assert html =~ "Content Breakdown"

      # Switch to French — no texts exist for French
      html = view |> render_change("change_locale", %{"locale" => "fr"})

      # French should still show VO Progress (always shown with locale)
      assert html =~ "Voice-Over Progress"
    end
  end
end
