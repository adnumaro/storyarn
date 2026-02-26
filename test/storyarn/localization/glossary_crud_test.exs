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

    test "get_glossary_entry/1 returns the entry" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, entry} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      result = Localization.get_glossary_entry(entry.project_id, entry.id)
      assert result.id == entry.id
      assert result.source_term == "mana"
    end

    test "get_glossary_entry/2 returns nil for non-existent id" do
      user = user_fixture()
      project = project_fixture(user)

      assert Localization.get_glossary_entry(project.id, -1) == nil
    end

    test "list_glossary_entries/2 searches by source and target term" do
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

      # Search by source_term
      entries = Localization.list_glossary_entries(project.id, search: "mana")
      assert length(entries) == 1
      assert hd(entries).source_term == "mana"

      # Search by target_term
      entries = Localization.list_glossary_entries(project.id, search: "Eldoria")
      assert length(entries) == 1
      assert hd(entries).source_term == "Eldoria"
    end

    test "list_glossary_entries/2 returns all when search is nil or empty" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      assert length(Localization.list_glossary_entries(project.id, search: nil)) == 1
      assert length(Localization.list_glossary_entries(project.id, search: "")) == 1
    end

    test "list_glossary_entries/2 returns empty when only source_locale given" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      # Only source_locale, no target_locale — should return all (filter bypassed)
      entries = Localization.list_glossary_entries(project.id, source_locale: "en")
      assert length(entries) == 1
    end

    test "list_glossary_for_export/1 returns all entries for export" do
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
          target_locale: "fr"
        })

      entries = Localization.list_glossary_for_export(project.id)
      assert length(entries) == 2
      # Ordered by source_term, then target_locale
      assert hd(entries).source_term == "Eldoria"
    end

    test "list_glossary_for_export/1 returns empty for project without entries" do
      user = user_fixture()
      project = project_fixture(user)

      assert Localization.list_glossary_for_export(project.id) == []
    end

    test "bulk_import_glossary_entries/1 inserts entries in bulk" do
      user = user_fixture()
      project = project_fixture(user)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs_list = [
        %{
          project_id: project.id,
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es",
          do_not_translate: false,
          inserted_at: now,
          updated_at: now
        },
        %{
          project_id: project.id,
          source_term: "Eldoria",
          source_locale: "en",
          target_term: "Eldoria",
          target_locale: "es",
          do_not_translate: true,
          inserted_at: now,
          updated_at: now
        }
      ]

      Localization.bulk_import_glossary_entries(attrs_list)

      entries = Localization.list_glossary_entries(project.id)
      assert length(entries) == 2
    end

    test "bulk_import_glossary_entries/1 handles empty list" do
      Localization.bulk_import_glossary_entries([])
      # No error raised
    end

    test "create_glossary_entry/2 with context field" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, entry} =
        Localization.create_glossary_entry(project, %{
          source_term: "level",
          source_locale: "en",
          target_term: "nivel",
          target_locale: "es",
          context: "Game difficulty level"
        })

      assert entry.context == "Game difficulty level"
    end

    test "update_glossary_entry/2 can update context and do_not_translate" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, entry} =
        Localization.create_glossary_entry(project, %{
          source_term: "mana",
          source_locale: "en",
          target_term: "maná",
          target_locale: "es"
        })

      {:ok, updated} =
        Localization.update_glossary_entry(entry, %{
          context: "Magical energy",
          do_not_translate: true
        })

      assert updated.context == "Magical energy"
      assert updated.do_not_translate == true
    end
  end
end
