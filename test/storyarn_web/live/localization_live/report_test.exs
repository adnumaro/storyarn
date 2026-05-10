defmodule StoryarnWeb.LocalizationLive.ReportTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp report_url(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization"
  end

  defp get_report_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/localization/report/Report")
  end

  describe "Localization report page" do
    setup :register_and_log_in_user

    test "renders Vue report component for owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.component == "live/localization/report/Report"
      assert is_list(vue.props["language-progress"])
      assert is_list(vue.props["target-languages"])
    end

    test "renders for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.component == "live/localization/report/Report"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, report_url(project))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "passes empty target-languages when no languages", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.props["target-languages"] == []
      assert vue.props["selected-locale"] == nil
    end

    test "passes target languages when they exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      target_codes = Enum.map(vue.props["target-languages"], & &1["localeCode"])
      assert "es" in target_codes
    end

    test "passes report language options to Vue", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert [%{"localeCode" => "es"}] = vue.props["target-languages"]
      assert vue.props["selected-locale"] == "es"
    end
  end

  describe "Locale selection" do
    setup :register_and_log_in_user

    test "change_locale event updates selected-locale prop", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} = live(conn, report_url(project))

      render_change(view, "change_locale", %{"locale" => "fr"})

      vue = get_report_vue(view)
      assert vue.props["selected-locale"] == "fr"
    end

    test "selected_locale defaults to first target language", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.props["selected-locale"] == "es"
    end
  end

  describe "Report data sections" do
    setup :register_and_log_in_user

    test "passes vo-progress when locale selected", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert is_map(vue.props["vo-progress"])
    end

    test "passes language-progress with language info", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert is_list(vue.props["language-progress"])
      assert length(vue.props["language-progress"]) >= 1
    end

    test "handles project with no localized texts", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.component == "live/localization/report/Report"
    end
  end

  describe "Viewer role" do
    setup :register_and_log_in_user

    test "viewer can access report page", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.component == "live/localization/report/Report"
    end

    test "viewer can change locale", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} = live(conn, report_url(project))

      render_change(view, "change_locale", %{"locale" => "fr"})

      vue = get_report_vue(view)
      assert vue.props["selected-locale"] == "fr"
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

  describe "Content breakdown with various source types" do
    setup :register_and_log_in_user

    test "type-counts includes flow_node", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      type_counts = vue.props["type-counts"]
      assert is_map(type_counts)
      assert Map.has_key?(type_counts, "flow_node")
    end

    test "type-counts includes block", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "block",
          source_field: "label",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      type_counts = vue.props["type-counts"]
      assert Map.has_key?(type_counts, "block")
    end

    test "type-counts includes sheet", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "sheet",
          source_field: "name",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert Map.has_key?(vue.props["type-counts"], "sheet")
    end

    test "type-counts includes flow", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow",
          source_field: "name",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert Map.has_key?(vue.props["type-counts"], "flow")
    end

    test "type-counts includes screenplay", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{
          source_type: "screenplay",
          source_field: "name",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert Map.has_key?(vue.props["type-counts"], "screenplay")
    end

    test "type-counts includes multiple source types", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
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

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      type_counts = vue.props["type-counts"]
      assert Map.has_key?(type_counts, "flow_node")
      assert Map.has_key?(type_counts, "block")
    end
  end

  describe "Empty state props" do
    setup :register_and_log_in_user

    test "speaker-stats is empty list when no texts with speakers", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.props["speaker-stats"] == []
    end

    test "type-counts is empty map when no texts", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.props["type-counts"] == %{}
    end

    test "selected-locale is nil when no target languages exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.props["selected-locale"] == nil
      assert vue.props["target-languages"] == []
    end
  end

  describe "Locale switching with content" do
    setup :register_and_log_in_user

    test "switching locale reloads data for the new locale", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      _text_es =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, report_url(project))

      vue = get_report_vue(view)
      assert vue.props["selected-locale"] == "es"

      render_change(view, "change_locale", %{"locale" => "fr"})

      vue = get_report_vue(view)
      assert vue.props["selected-locale"] == "fr"
    end
  end
end
