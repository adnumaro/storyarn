defmodule Storyarn.Localization.GlossaryCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Localization

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  describe "glossary entries" do
    test "create_glossary_entry/2 creates an entry" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, entry} =
        Localization.create_glossary_entry(project, %{
          source_term: "Eldoria",
          source_locale: "en",
          target_term: "Eldoria",
          target_locale: "es",
          do_not_translate: true
        })

      assert entry.source_term == "Eldoria"
      assert entry.source_locale == "en"
      assert entry.target_term == "Eldoria"
      assert entry.target_locale == "es"
      assert entry.do_not_translate == true
    end

    test "create_glossary_entry/2 validates required fields" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Localization.create_glossary_entry(project, %{})

      assert "can't be blank" in errors_on(changeset).source_term
      assert "can't be blank" in errors_on(changeset).source_locale
      assert "can't be blank" in errors_on(changeset).target_locale
    end

    test "create_glossary_entry/2 enforces unique constraint" do
      user = user_fixture()
      project = project_fixture(user)

      attrs = %{
        source_term: "mana",
        source_locale: "en",
        target_term: "maná",
        target_locale: "es"
      }

      {:ok, _} = Localization.create_glossary_entry(project, attrs)
      {:error, _changeset} = Localization.create_glossary_entry(project, attrs)
    end

    test "list_glossary_entries/2 returns all entries for a project" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      {:ok, _} =
        Localization.create_glossary_entry(project, %{
          source_term: "Eldoria",
          source_locale: "en",
          target_term: "Eldoria",
          target_locale: "es"
        })

      entries = Localization.list_glossary_entries(project.id)
      assert length(entries) == 2
      # Ordered by source_term
      assert hd(entries).source_term == "Eldoria"
    end

    test "list_glossary_entries/2 filters by locale pair" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      {:ok, _} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "マナ",
          target_locale: "ja"
        })

      entries =
        Localization.list_glossary_entries(project.id, source_locale: "en", target_locale: "es")

      assert length(entries) == 1
      assert hd(entries).target_locale == "es"
    end

    test "get_glossary_entries_for_pair/3 returns tuples" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      pairs = Localization.get_glossary_entries_for_pair(project.id, "en", "es")
      assert pairs == [{"mana", "maná"}]
    end

    test "update_glossary_entry/2 updates an entry" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, entry} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      {:ok, updated} = Localization.update_glossary_entry(entry, %{target_term: "mana (updated)"})
      assert updated.target_term == "mana (updated)"
    end

    test "delete_glossary_entry/1 deletes an entry" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, entry} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      {:ok, _} = Localization.delete_glossary_entry(entry)
      assert Localization.list_glossary_entries(project.id) == []
    end
  end
end
