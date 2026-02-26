defmodule StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpersExtendedTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.LocalizationFixtures

  alias Storyarn.{Localization, Repo}
  alias StoryarnWeb.LocalizationLive.Helpers.LocalizationHelpers

  # ── strip_html/1 ────────────────────────────────────────────────

  describe "strip_html/1" do
    test "strips HTML tags from text" do
      result = LocalizationHelpers.strip_html("<p>Hello <b>World</b></p>")
      assert result =~ "Hello"
      assert result =~ "World"
      refute result =~ "<p>"
      refute result =~ "<b>"
    end

    test "handles nil" do
      result = LocalizationHelpers.strip_html(nil)
      assert result == "" or is_nil(result)
    end

    test "returns plain text unchanged" do
      assert LocalizationHelpers.strip_html("Just plain text") == "Just plain text"
    end

    test "strips nested HTML" do
      result = LocalizationHelpers.strip_html("<div><p>Nested <em>content</em></p></div>")
      assert result =~ "Nested"
      assert result =~ "content"
    end
  end

  # ── has_active_provider?/1 ─────────────────────────────────────

  describe "has_active_provider?/1" do
    setup do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "returns false when no provider configured", %{project: project} do
      refute LocalizationHelpers.has_active_provider?(project.id)
    end
  end

  # ── language_picker_options/1 ──────────────────────────────────

  describe "language_picker_options/1" do
    setup do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "returns options excluding existing languages", %{project: project} do
      _lang = language_fixture(project, %{locale_code: "en", name: "English"})

      languages = Localization.list_languages(project.id)
      assigns = %{languages: languages}
      options = LocalizationHelpers.language_picker_options(assigns)

      # English should not be in options
      codes = Enum.map(options, fn {_label, code} -> code end)
      refute "en" in codes
    end

    test "returns all options when no languages exist", %{project: _project} do
      assigns = %{languages: []}
      options = LocalizationHelpers.language_picker_options(assigns)
      assert options != []
    end
  end

  # ── load_texts/1 ─────────────────────────────────────────────

  describe "load_texts/1" do
    setup do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      _source = language_fixture(project, %{locale_code: "en", name: "English", is_source: true})
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      %{project: project}
    end

    test "sets empty texts when locale is nil", %{project: project} do
      socket = build_socket(project, nil)
      result = LocalizationHelpers.load_texts(socket)

      assert result.assigns.texts == []
      assert result.assigns.total_count == 0
      assert is_nil(result.assigns.progress)
    end

    test "loads texts for selected locale", %{project: project} do
      socket = build_socket(project, "es")
      result = LocalizationHelpers.load_texts(socket)

      assert result.assigns.texts == []
      assert result.assigns.total_count == 0
    end

    test "applies filter_status when set", %{project: project} do
      socket = build_socket(project, "es", filter_status: "pending")
      result = LocalizationHelpers.load_texts(socket)

      assert result.assigns.texts == []
    end

    test "applies search filter when set", %{project: project} do
      socket = build_socket(project, "es", search: "hello")
      result = LocalizationHelpers.load_texts(socket)

      assert result.assigns.texts == []
    end
  end

  # ── reload_languages/1 ────────────────────────────────────────

  describe "reload_languages/1" do
    setup do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "sets selected_locale to nil when no target languages", %{project: project} do
      socket = build_socket(project, nil)
      result = LocalizationHelpers.reload_languages(socket)

      assert result.assigns.languages == []
      assert result.assigns.target_languages == []
      assert is_nil(result.assigns.selected_locale)
    end

    test "selects first target language when current not in list", %{project: project} do
      _source = language_fixture(project, %{locale_code: "en", name: "English", is_source: true})
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      socket = build_socket(project, "fr")
      result = LocalizationHelpers.reload_languages(socket)

      assert result.assigns.selected_locale == "es"
    end

    test "preserves current locale if still valid", %{project: project} do
      _source = language_fixture(project, %{locale_code: "en", name: "English", is_source: true})
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      socket = build_socket(project, "es")
      result = LocalizationHelpers.reload_languages(socket)

      assert result.assigns.selected_locale == "es"
    end

    test "resets page to 1 when locale changes", %{project: project} do
      _source = language_fixture(project, %{locale_code: "en", name: "English", is_source: true})
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      socket = build_socket(project, "fr", page: 3)
      result = LocalizationHelpers.reload_languages(socket)

      assert result.assigns.page == 1
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp build_socket(project, selected_locale, opts \\ []) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        project: project,
        selected_locale: selected_locale,
        page_size: Keyword.get(opts, :page_size, 25),
        page: Keyword.get(opts, :page, 1),
        filter_status: Keyword.get(opts, :filter_status, nil),
        filter_source_type: Keyword.get(opts, :filter_source_type, nil),
        search: Keyword.get(opts, :search, ""),
        __changed__: %{}
      }
    }
  end
end
