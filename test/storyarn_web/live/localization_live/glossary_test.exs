defmodule StoryarnWeb.LocalizationLive.GlossaryTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Repo

  defp glossary_path(project, locale \\ "es") do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/glossary/#{locale}"
  end

  defp get_glossary_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/localization/glossary/LocalizationGlossary")
  end

  setup :register_and_log_in_user

  test "renders the selected glossary pair", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    {:ok, view, _html} = live(conn, glossary_path(project))
    vue = get_glossary_vue(view)

    assert vue.props["source-language"]["localeCode"] == "en"
    assert vue.props["selected-locale"] == "es"
    assert vue.props["entries"] == []
  end

  test "creates and updates glossary entries inline", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    {:ok, view, _html} = live(conn, glossary_path(project))

    render_hook(view, "save_entry", %{
      "source_term" => "sword",
      "target_term" => "espada",
      "context" => "Weapon",
      "do_not_translate" => false
    })

    [entry] = Localization.list_glossary_entries(project.id)
    assert entry.target_term == "espada"
    assert [serialized] = get_glossary_vue(view).props["entries"]
    assert serialized["sourceTerm"] == "sword"

    render_hook(view, "save_entry", %{
      "id" => entry.id,
      "source_term" => entry.source_term,
      "target_term" => "hoja",
      "context" => "Weapon",
      "do_not_translate" => false
    })

    assert Localization.get_glossary_entry(project.id, entry.id).target_term == "hoja"
  end

  test "viewer cannot mutate entries", %{conn: conn, user: user} do
    owner = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    _membership = membership_fixture(project, user, "viewer")
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    {:ok, view, _html} = live(conn, glossary_path(project))

    render_hook(view, "save_entry", %{
      "source_term" => "sword",
      "target_term" => "espada",
      "do_not_translate" => false
    })

    assert Localization.list_glossary_entries(project.id) == []
  end

  test "sync remains stable when the route has no valid target locale", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})

    {:ok, view, _html} = live(conn, glossary_path(project, "unknown"))

    render_hook(view, "sync_glossary", %{})
    assert get_glossary_vue(view).props["selected-locale"] == nil
  end

  test "clears a selected locale after that target language is archived", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    {:ok, view, _html} = live(conn, glossary_path(project))
    assert get_glossary_vue(view).props["selected-locale"] == "es"

    assert {:ok, _archived} = Localization.remove_language(target)
    send(view.pid, {:languages_changed, nil})
    render(view)

    assert get_glossary_vue(view).props["selected-locale"] == nil
    assert get_glossary_vue(view).props["entries"] == []
  end
end
