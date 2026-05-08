defmodule StoryarnWeb.LocalizationLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Repo

  defp loc_path(project, locale \\ "es") do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/texts/#{locale}"
  end

  defp get_index_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/localization/components/LocalizationIndex")
  end

  defp get_sidebar_props(view) do
    # Sidebar props are passed via tree-props to the MainSidebar, which passes them to the component.
    # We read them from the layout's tree-props attribute via the MainSidebar vue.
    main_sidebar = LiveVue.Test.get_vue(view, name: "layout/MainSidebar")
    main_sidebar.props["sidebar-props"]
  end

  defp get_sidebar_live(view, project) do
    find_live_child(view, "sidebar-localization-#{project.id}")
  end

  describe "Localization index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert vue.component == "modules/localization/components/LocalizationIndex"
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert vue.component == "modules/localization/components/LocalizationIndex"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, loc_path(project))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "passes texts to Vue when target language and texts exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      texts = vue.props["texts"]
      assert is_list(texts)
      assert Enum.any?(texts, fn t -> t["sourceText"] == "Hello world" end)
    end

    test "passes hasTargetLanguages=false when no target languages", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert vue.props["has-target-languages"] == false
    end

    test "passes sidebar props with source language", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_props(view)
      assert sidebar["sourceLanguage"]["localeCode"] == "en"
    end

    test "does not include source language in add language options", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_props(view)
      values = Enum.map(sidebar["addLanguageOptions"], & &1["value"])
      refute "en" in values
    end

    test "passes flag URLs for source and target locales", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_props(view)
      assert sidebar["sourceLanguage"]["flagUrl"] =~ "/images/flags/"
      [target | _] = sidebar["targetLanguages"]
      assert target["flagUrl"] =~ "/images/flags/"
    end

    test "passes progress data when texts exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert vue.props["progress"]["total"] >= 1
    end

    test "passes status labels in serialized texts", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      text = hd(vue.props["texts"])
      assert text["statusLabel"] == "Pending"
    end

    test "defaults selected locale to first target language", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_props(view)
      assert sidebar["selectedLocale"] == "es"
      assert length(sidebar["targetLanguages"]) == 2
    end
  end

  describe "change_locale event" do
    setup :register_and_log_in_user

    test "switches selected locale and reloads texts", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      _text_es =
        localized_text_fixture(project.id, %{source_text: "Spanish text", locale_code: "es"})

      _text_fr =
        localized_text_fixture(project.id, %{source_text: "French text", locale_code: "fr"})

      {:ok, view, _html} = live(conn, loc_path(project))

      # Initial render shows es texts
      vue = get_index_vue(view)
      assert Enum.any?(vue.props["texts"], fn t -> t["sourceText"] == "Spanish text" end)

      render_patch(view, loc_path(project, "fr"))

      vue = get_index_vue(view)
      assert Enum.any?(vue.props["texts"], fn t -> t["sourceText"] == "French text" end)
    end
  end

  describe "change_source_language event" do
    setup :register_and_log_in_user

    test "updates the project's source language", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_live(view, project)
      render_click(sidebar, "change_source_language", %{"locale_code" => "en-US"})

      source_language = Localization.get_source_language(project.id)
      assert source_language.locale_code == "en-US"
    end

    test "viewer cannot change source language", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_live(view, project)
      render_click(sidebar, "change_source_language", %{"locale_code" => "en-US"})

      source_language = Localization.get_source_language(project.id)
      assert source_language.locale_code == "en"
    end
  end

  describe "change_filter event" do
    setup :register_and_log_in_user

    test "filters by status", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
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

      {:ok, view, _html} = live(conn, loc_path(project))

      # Both texts initially
      vue = get_index_vue(view)
      source_texts = Enum.map(vue.props["texts"], & &1["sourceText"])
      assert "Pending text here" in source_texts
      assert "Final text here" in source_texts

      # Filter by "final" status
      render_click(view, "change_filter", %{"status" => "final"})

      vue = get_index_vue(view)
      source_texts = Enum.map(vue.props["texts"], & &1["sourceText"])
      assert "Final text here" in source_texts
      refute "Pending text here" in source_texts
    end

    test "filters by source_type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
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

      {:ok, view, _html} = live(conn, loc_path(project))

      render_click(view, "change_filter", %{"source_type" => "block"})

      vue = get_index_vue(view)
      source_texts = Enum.map(vue.props["texts"], & &1["sourceText"])
      assert "Block text" in source_texts
      refute "Flow node text" in source_texts
    end

    test "empty status value clears current filter", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
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

      {:ok, view, _html} = live(conn, loc_path(project))

      render_click(view, "change_filter", %{"status" => "final"})
      render_click(view, "change_filter", %{"status" => ""})

      vue = get_index_vue(view)
      source_texts = Enum.map(vue.props["texts"], & &1["sourceText"])
      assert "Final text here" in source_texts
      assert "Pending text here" in source_texts
    end
  end

  describe "search event" do
    setup :register_and_log_in_user

    test "filters texts by search term", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text1 =
        localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      _text2 =
        localized_text_fixture(project.id, %{source_text: "Goodbye world", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      render_click(view, "search", %{"search" => "Hello"})

      vue = get_index_vue(view)
      source_texts = Enum.map(vue.props["texts"], & &1["sourceText"])
      assert "Hello world" in source_texts
      refute "Goodbye world" in source_texts
    end

    test "shows empty texts when search matches nothing", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      render_click(view, "search", %{"search" => "nonexistent_xyz"})

      vue = get_index_vue(view)
      assert vue.props["texts"] == []
    end

    test "clears search with empty string", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _text = localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      render_click(view, "search", %{"search" => "nonexistent_xyz"})
      render_click(view, "search", %{"search" => ""})

      vue = get_index_vue(view)
      assert Enum.any?(vue.props["texts"], fn t -> t["sourceText"] == "Hello world" end)
    end
  end

  describe "change_page event" do
    setup :register_and_log_in_user

    test "paginates to next page", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      for i <- 1..52 do
        localized_text_fixture(project.id, %{
          source_text: "Text number #{i}",
          locale_code: "es",
          source_id: System.unique_integer([:positive])
        })
      end

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert vue.props["pagination"]["page"] == 1
      assert vue.props["total-count"] == 52

      render_click(view, "change_page", %{"page" => "2"})

      vue = get_index_vue(view)
      assert vue.props["pagination"]["page"] == 2
    end
  end

  describe "add_target_language event" do
    setup :register_and_log_in_user

    test "adds a new target language", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert vue.props["has-target-languages"] == false

      sidebar = get_sidebar_live(view, project)
      render_click(sidebar, "add_target_language", %{"locale_code" => "fr"})

      assert Localization.get_language_by_locale(project.id, "fr")

      render(view)
      sidebar = get_sidebar_props(view)
      assert Enum.any?(sidebar["targetLanguages"], fn l -> l["localeCode"] == "fr" end)
    end

    test "no-op when locale_code is empty", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_live(view, project)
      render_click(sidebar, "add_target_language", %{"locale_code" => ""})

      vue = get_index_vue(view)
      assert vue.props["has-target-languages"] == false
    end

    test "viewer cannot add target language", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_live(view, project)
      render_click(sidebar, "add_target_language", %{"locale_code" => "fr"})

      refute Localization.get_language_by_locale(project.id, "fr")
    end
  end

  describe "remove_language event" do
    setup :register_and_log_in_user

    test "removes a target language", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_props(view)
      assert Enum.any?(sidebar["targetLanguages"], fn l -> l["localeCode"] == "es" end)

      sidebar_live = get_sidebar_live(view, project)
      render_click(sidebar_live, "remove_language", %{"id" => language.id})

      refute Localization.get_language(project.id, language.id)

      render(view)
      vue = get_index_vue(view)
      assert vue.props["has-target-languages"] == false
    end

    test "viewer cannot remove a language", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_live(view, project)
      render_click(sidebar, "remove_language", %{"id" => language.id})

      assert Localization.get_language(project.id, language.id)
    end
  end

  describe "sync_texts event" do
    setup :register_and_log_in_user

    test "syncs texts for the project", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      sidebar = get_sidebar_live(view, project)
      html = render_click(sidebar, "sync_texts", %{})

      assert is_binary(html)
    end

    test "viewer cannot sync texts", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      before_count = Localization.count_texts(project.id)

      sidebar = get_sidebar_live(view, project)
      html = render_click(sidebar, "sync_texts", %{})

      assert is_binary(html)
      assert Localization.count_texts(project.id) == before_count
    end
  end

  describe "translate_batch event" do
    setup :register_and_log_in_user

    test "viewer does not render the batch translation toolbar", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, view, _html} = live(conn, loc_path(project))

      refute has_element?(view, "#localization-toolbar-#{project.id}")
    end
  end

  describe "translate_single event" do
    setup :register_and_log_in_user

    test "viewer cannot translate single text", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      text =
        localized_text_fixture(project.id, %{source_text: "Hello", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      html = render_click(view, "translate_single", %{"id" => "#{text.id}"})
      reloaded_text = Localization.get_text(project.id, text.id)

      assert is_binary(html)
      assert reloaded_text.translated_text == text.translated_text
      assert reloaded_text.status == text.status
    end
  end

  describe "Viewer role restrictions" do
    setup :register_and_log_in_user

    test "viewer sees canEdit=false in sidebar and index", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert vue.props["can-edit"] == false

      sidebar = get_sidebar_props(view)
      assert sidebar["canEdit"] == false
    end

    test "viewer can view texts", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{source_text: "Viewable text", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      vue = get_index_vue(view)
      assert Enum.any?(vue.props["texts"], fn t -> t["sourceText"] == "Viewable text" end)

      sidebar = get_sidebar_props(view)
      assert Enum.any?(sidebar["targetLanguages"], fn l -> l["localeCode"] == "es" end)
    end

    test "viewer can change locale", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _lang_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _lang_fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      {:ok, view, _html} = live(conn, loc_path(project))

      render_patch(view, loc_path(project, "fr"))

      sidebar = get_sidebar_props(view)
      assert sidebar["selectedLocale"] == "fr"
    end

    test "viewer can use search", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{source_text: "Searchable text", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      render_click(view, "search", %{"search" => "Searchable"})

      vue = get_index_vue(view)
      assert Enum.any?(vue.props["texts"], fn t -> t["sourceText"] == "Searchable text" end)
    end

    test "viewer can use filters", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        localized_text_fixture(project.id, %{source_text: "Filter me", locale_code: "es"})

      {:ok, view, _html} = live(conn, loc_path(project))

      render_click(view, "change_filter", %{"status" => "pending"})

      vue = get_index_vue(view)
      assert Enum.any?(vue.props["texts"], fn t -> t["sourceText"] == "Filter me" end)
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/localization/texts/es")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
