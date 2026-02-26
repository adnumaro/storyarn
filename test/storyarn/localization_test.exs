defmodule Storyarn.LocalizationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Localization

  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # Project Languages
  # =============================================================================

  describe "project_languages" do
    test "list_languages/1 returns all languages for a project" do
      user = user_fixture()
      project = project_fixture(user)
      lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      languages = Localization.list_languages(project.id)

      assert length(languages) == 1
      assert hd(languages).id == lang.id
    end

    test "list_languages/1 returns empty list for project without languages" do
      user = user_fixture()
      project = project_fixture(user)

      assert Localization.list_languages(project.id) == []
    end

    test "list_languages/1 orders by position then name" do
      user = user_fixture()
      project = project_fixture(user)
      _fr = language_fixture(project, %{locale_code: "fr", name: "French", position: 2})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish", position: 0})
      _de = language_fixture(project, %{locale_code: "de", name: "German", position: 1})

      languages = Localization.list_languages(project.id)

      assert Enum.map(languages, & &1.locale_code) == ["es", "de", "fr"]
    end

    test "add_language/2 creates a language" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, lang} = Localization.add_language(project, %{locale_code: "ja", name: "Japanese"})

      assert lang.locale_code == "ja"
      assert lang.name == "Japanese"
      assert lang.project_id == project.id
      assert lang.is_source == false
    end

    test "add_language/2 creates a source language" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, lang} =
        Localization.add_language(project, %{locale_code: "en", name: "English", is_source: true})

      assert lang.is_source == true
    end

    test "add_language/2 validates required fields" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Localization.add_language(project, %{})

      assert "can't be blank" in errors_on(changeset).locale_code
      assert "can't be blank" in errors_on(changeset).name
    end

    test "add_language/2 enforces unique locale_code per project" do
      user = user_fixture()
      project = project_fixture(user)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:error, changeset} =
        Localization.add_language(project, %{locale_code: "es", name: "Spanish 2"})

      errors = errors_on(changeset)
      # Unique constraint on [:project_id, :locale_code] reports on first field
      assert "has already been taken" in (errors[:locale_code] || errors[:project_id] || [])
    end

    test "add_language/2 auto-assigns next position" do
      user = user_fixture()
      project = project_fixture(user)
      lang1 = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      lang2 = language_fixture(project, %{locale_code: "fr", name: "French"})

      assert lang1.position == 0
      assert lang2.position == 1
    end

    test "get_language/2 returns the language" do
      user = user_fixture()
      project = project_fixture(user)
      lang = language_fixture(project)

      result = Localization.get_language(project.id, lang.id)
      assert result.id == lang.id
    end

    test "get_language/2 returns nil for non-existent language" do
      user = user_fixture()
      project = project_fixture(user)

      assert Localization.get_language(project.id, -1) == nil
    end

    test "get_language_by_locale/2 returns the language" do
      user = user_fixture()
      project = project_fixture(user)
      _lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      result = Localization.get_language_by_locale(project.id, "es")
      assert result.locale_code == "es"
    end

    test "get_source_language/1 returns the source language" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      result = Localization.get_source_language(project.id)
      assert result.locale_code == "en"
      assert result.is_source == true
    end

    test "get_target_languages/1 returns non-source languages" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      targets = Localization.get_target_languages(project.id)
      assert length(targets) == 2
      assert Enum.all?(targets, &(&1.is_source == false))
    end

    test "update_language/2 updates a language" do
      user = user_fixture()
      project = project_fixture(user)
      lang = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, updated} = Localization.update_language(lang, %{name: "Español"})
      assert updated.name == "Español"
    end

    test "remove_language/1 deletes a language" do
      user = user_fixture()
      project = project_fixture(user)
      lang = language_fixture(project)

      {:ok, _deleted} = Localization.remove_language(lang)
      assert Localization.list_languages(project.id) == []
    end

    test "set_source_language/1 changes source language" do
      user = user_fixture()
      project = project_fixture(user)
      en = source_language_fixture(project)
      es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      {:ok, new_source} = Localization.set_source_language(es)
      assert new_source.is_source == true

      # Old source should no longer be source
      old = Localization.get_language(project.id, en.id)
      assert old.is_source == false
    end

    test "reorder_languages/2 updates positions" do
      user = user_fixture()
      project = project_fixture(user)
      es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      fr = language_fixture(project, %{locale_code: "fr", name: "French"})
      de = language_fixture(project, %{locale_code: "de", name: "German"})

      {:ok, _} = Localization.reorder_languages(project.id, [de.id, fr.id, es.id])

      languages = Localization.list_languages(project.id)
      assert Enum.map(languages, & &1.locale_code) == ["de", "fr", "es"]
    end
  end

  # =============================================================================
  # Localized Texts
  # =============================================================================

  describe "localized_texts" do
    test "create_text/2 creates a localized text" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, text} =
        Localization.create_text(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          source_field: "text",
          source_text: "Hello, world!",
          source_text_hash: hash("Hello, world!"),
          locale_code: "es",
          word_count: 2
        })

      assert text.source_type == "flow_node"
      assert text.source_id == 42
      assert text.source_field == "text"
      assert text.source_text == "Hello, world!"
      assert text.locale_code == "es"
      assert text.status == "pending"
      assert text.word_count == 2
      assert text.project_id == project.id
    end

    test "create_text/2 validates required fields" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Localization.create_text(project.id, %{})

      assert "can't be blank" in errors_on(changeset).source_type
      assert "can't be blank" in errors_on(changeset).source_id
      assert "can't be blank" in errors_on(changeset).source_field
      assert "can't be blank" in errors_on(changeset).locale_code
    end

    test "create_text/2 validates source_type inclusion" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} =
        Localization.create_text(project.id, %{
          source_type: "invalid",
          source_id: 1,
          source_field: "text",
          locale_code: "es"
        })

      assert "is invalid" in errors_on(changeset).source_type
    end

    test "create_text/2 enforces unique composite key" do
      user = user_fixture()
      project = project_fixture(user)

      attrs = %{
        source_type: "flow_node",
        source_id: 42,
        source_field: "text",
        locale_code: "es"
      }

      {:ok, _} = Localization.create_text(project.id, attrs)
      {:error, changeset} = Localization.create_text(project.id, attrs)

      assert errors_on(changeset)[:source_type] != nil ||
               errors_on(changeset)[:source_id] != nil ||
               errors_on(changeset)[:source_field] != nil ||
               errors_on(changeset)[:locale_code] != nil
    end

    test "list_texts/2 returns texts for a project" do
      user = user_fixture()
      project = project_fixture(user)
      text = localized_text_fixture(project.id)

      texts = Localization.list_texts(project.id)
      assert length(texts) == 1
      assert hd(texts).id == text.id
    end

    test "list_texts/2 filters by locale_code" do
      user = user_fixture()
      project = project_fixture(user)
      _es = localized_text_fixture(project.id, %{locale_code: "es", source_id: 1})
      _fr = localized_text_fixture(project.id, %{locale_code: "fr", source_id: 2})

      texts = Localization.list_texts(project.id, locale_code: "es")
      assert length(texts) == 1
      assert hd(texts).locale_code == "es"
    end

    test "list_texts/2 filters by status" do
      user = user_fixture()
      project = project_fixture(user)
      _pending = localized_text_fixture(project.id, %{source_id: 1})

      {:ok, _draft} =
        Localization.create_text(project.id, %{
          source_type: "flow_node",
          source_id: 2,
          source_field: "text",
          locale_code: "es",
          status: "draft"
        })

      texts = Localization.list_texts(project.id, status: "draft")
      assert length(texts) == 1
      assert hd(texts).status == "draft"
    end

    test "list_texts/2 filters by source_type" do
      user = user_fixture()
      project = project_fixture(user)
      _node = localized_text_fixture(project.id, %{source_type: "flow_node", source_id: 1})
      _block = localized_text_fixture(project.id, %{source_type: "block", source_id: 2})

      texts = Localization.list_texts(project.id, source_type: "block")
      assert length(texts) == 1
      assert hd(texts).source_type == "block"
    end

    test "list_texts/2 searches in source_text and translated_text" do
      user = user_fixture()
      project = project_fixture(user)
      _text1 = localized_text_fixture(project.id, %{source_text: "Hello world", source_id: 1})
      _text2 = localized_text_fixture(project.id, %{source_text: "Goodbye moon", source_id: 2})

      texts = Localization.list_texts(project.id, search: "Hello")
      assert length(texts) == 1
    end

    test "count_texts/2 returns the count" do
      user = user_fixture()
      project = project_fixture(user)
      _text1 = localized_text_fixture(project.id, %{source_id: 1})
      _text2 = localized_text_fixture(project.id, %{source_id: 2})

      assert Localization.count_texts(project.id) == 2
      assert Localization.count_texts(project.id, locale_code: "es") == 2
      assert Localization.count_texts(project.id, locale_code: "fr") == 0
    end

    test "get_text/1 returns the text" do
      user = user_fixture()
      project = project_fixture(user)
      text = localized_text_fixture(project.id)

      result = Localization.get_text(text.id)
      assert result.id == text.id
    end

    test "get_text_by_source/4 returns the text by composite key" do
      user = user_fixture()
      project = project_fixture(user)

      text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          source_field: "text",
          locale_code: "es"
        })

      result = Localization.get_text_by_source("flow_node", 42, "text", "es")
      assert result.id == text.id
    end

    test "get_texts_for_source/2 returns all locale texts for a source" do
      user = user_fixture()
      project = project_fixture(user)

      _es =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          locale_code: "es"
        })

      _fr =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          locale_code: "fr"
        })

      texts = Localization.get_texts_for_source("flow_node", 42)
      assert length(texts) == 2
    end

    test "update_text/2 updates translation" do
      user = user_fixture()
      project = project_fixture(user)
      text = localized_text_fixture(project.id)

      {:ok, updated} =
        Localization.update_text(text, %{
          translated_text: "Hola mundo",
          status: "draft",
          machine_translated: true
        })

      assert updated.translated_text == "Hola mundo"
      assert updated.status == "draft"
      assert updated.machine_translated == true
    end

    test "upsert_text/2 creates when not exists" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, text} =
        Localization.upsert_text(project.id, %{
          source_type: "flow_node",
          source_id: 99,
          source_field: "text",
          source_text: "New text",
          source_text_hash: hash("New text"),
          locale_code: "es"
        })

      assert text.source_text == "New text"
    end

    test "upsert_text/2 updates source_text when hash changes" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _original} =
        Localization.upsert_text(project.id, %{
          source_type: "flow_node",
          source_id: 99,
          source_field: "text",
          source_text: "Original",
          source_text_hash: hash("Original"),
          locale_code: "es"
        })

      {:ok, updated} =
        Localization.upsert_text(project.id, %{
          source_type: "flow_node",
          source_id: 99,
          source_field: "text",
          source_text: "Updated",
          source_text_hash: hash("Updated"),
          locale_code: "es"
        })

      assert updated.source_text == "Updated"
    end

    test "upsert_text/2 downgrades final status to review when source changes" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, text} =
        Localization.create_text(project.id, %{
          source_type: "flow_node",
          source_id: 99,
          source_field: "text",
          source_text: "Original",
          source_text_hash: hash("Original"),
          locale_code: "es",
          status: "final"
        })

      # Manually set to final (simulating workflow completion)
      {:ok, _final_text} = Localization.update_text(text, %{status: "final"})

      {:ok, updated} =
        Localization.upsert_text(project.id, %{
          source_type: "flow_node",
          source_id: 99,
          source_field: "text",
          source_text: "Changed",
          source_text_hash: hash("Changed"),
          locale_code: "es"
        })

      assert updated.status == "review"
    end

    test "upsert_text/2 does not update when hash is unchanged" do
      user = user_fixture()
      project = project_fixture(user)

      hash_val = hash("Same text")

      {:ok, original} =
        Localization.upsert_text(project.id, %{
          source_type: "flow_node",
          source_id: 99,
          source_field: "text",
          source_text: "Same text",
          source_text_hash: hash_val,
          locale_code: "es"
        })

      {:ok, result} =
        Localization.upsert_text(project.id, %{
          source_type: "flow_node",
          source_id: 99,
          source_field: "text",
          source_text: "Same text",
          source_text_hash: hash_val,
          locale_code: "es"
        })

      assert result.id == original.id
      assert result.updated_at == original.updated_at
    end

    test "delete_texts_for_source/2 removes all texts for a source" do
      user = user_fixture()
      project = project_fixture(user)

      _es =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          locale_code: "es"
        })

      _fr =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          locale_code: "fr",
          source_field: "text"
        })

      {count, _} = Localization.delete_texts_for_source("flow_node", 42)
      assert count == 2
      assert Localization.get_texts_for_source("flow_node", 42) == []
    end

    test "delete_texts_for_source_field/3 removes texts for a specific field" do
      user = user_fixture()
      project = project_fixture(user)

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          source_field: "response.r1.text",
          locale_code: "es"
        })

      _main =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 42,
          source_field: "text",
          locale_code: "es"
        })

      {count, _} =
        Localization.delete_texts_for_source_field("flow_node", 42, "response.r1.text")

      assert count == 1
      # Main text should still exist
      assert Localization.get_text_by_source("flow_node", 42, "text", "es") != nil
    end

    test "get_progress/2 returns translation stats" do
      user = user_fixture()
      project = project_fixture(user)

      # Create texts with different statuses
      _pending = localized_text_fixture(project.id, %{source_id: 1})

      {:ok, _draft} =
        Localization.create_text(project.id, %{
          source_type: "flow_node",
          source_id: 2,
          source_field: "text",
          locale_code: "es",
          status: "draft"
        })

      {:ok, _final} =
        Localization.create_text(project.id, %{
          source_type: "flow_node",
          source_id: 3,
          source_field: "text",
          locale_code: "es",
          status: "final"
        })

      progress = Localization.get_progress(project.id, "es")

      assert progress.total == 3
      assert progress.pending == 1
      assert progress.draft == 1
      assert progress.final == 1
      assert progress.in_progress == 0
      assert progress.review == 0
    end
  end

  # =============================================================================
  # Provider Configuration
  # =============================================================================

  describe "provider_config" do
    test "get_provider_config/1 returns nil when no config exists" do
      user = user_fixture()
      project = project_fixture(user)

      assert Localization.get_provider_config(project.id) == nil
    end

    test "has_active_provider?/1 returns false when no config exists" do
      user = user_fixture()
      project = project_fixture(user)

      refute Localization.has_active_provider?(project.id)
    end

    test "upsert_provider_config/2 creates config when none exists" do
      user = user_fixture()
      project = project_fixture(user)

      attrs = %{
        "is_active" => true,
        "api_endpoint" => "https://api-free.deepl.com"
      }

      assert {:ok, config} = Localization.upsert_provider_config(project, attrs)
      assert config.project_id == project.id
      assert config.provider == "deepl"
      assert config.is_active == true
    end

    test "upsert_provider_config/2 updates existing config" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _config} =
        Localization.upsert_provider_config(project, %{
          "is_active" => true,
          "api_endpoint" => "https://api-free.deepl.com"
        })

      {:ok, updated} =
        Localization.upsert_provider_config(project, %{
          "is_active" => false
        })

      assert updated.is_active == false
    end

    test "change_provider_config/0 returns changeset with defaults" do
      changeset = Localization.change_provider_config()
      assert %Ecto.Changeset{} = changeset
    end

    test "change_provider_config/1 returns changeset for existing config" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, config} =
        Localization.upsert_provider_config(project, %{
          "is_active" => true,
          "api_endpoint" => "https://api-free.deepl.com"
        })

      changeset = Localization.change_provider_config(config)
      assert %Ecto.Changeset{} = changeset
    end
  end

  # =============================================================================
  # Static Language Helpers
  # =============================================================================

  describe "language helpers" do
    test "language_name/1 returns display name for a language code" do
      assert Localization.language_name("en") == "English"
      assert Localization.language_name("es") == "Spanish"
    end

    test "language_options_for_select/0 returns list of {label, code} tuples" do
      options = Localization.language_options_for_select()
      assert length(options) > 0

      {label, code} = hd(options)
      assert is_binary(label)
      assert is_binary(code)
    end

    test "change_localized_text/1 returns a valid changeset" do
      user = user_fixture()
      project = project_fixture(user)
      text = localized_text_fixture(project.id)

      changeset = Localization.change_localized_text(text)
      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "change_localized_text/2 returns a changeset with changes" do
      user = user_fixture()
      project = project_fixture(user)
      text = localized_text_fixture(project.id)

      changeset = Localization.change_localized_text(text, %{translated_text: "Hola"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :translated_text) == "Hola"
    end
  end

  # =============================================================================
  # Text Extraction
  # =============================================================================

  describe "extract_all/1" do
    test "extracts texts for a project with no flows or sheets" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, count} = Localization.extract_all(project.id)
      assert count == 0
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp hash(text) do
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end
end
