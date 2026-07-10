defmodule Storyarn.Localization.BatchTranslatorTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.TextCrud
  alias Storyarn.TestSupport.FakeTranslationProvider

  describe "translate_batch/3" do
    test "returns error when no provider is configured" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      assert {:error, :no_provider_configured} =
               Localization.translate_batch(project.id, "es")
    end

    test "returns error when no source language is configured" do
      user = user_fixture()
      project = project_fixture(user)
      # Only target, no source
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      # Create a provider config
      create_provider_config(project.id)

      assert {:error, :no_source_language} =
               Localization.translate_batch(project.id, "es")
    end

    test "returns error when no API key is set" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      # Create config without API key
      create_provider_config(project.id, api_key: nil)

      assert {:error, :no_api_key} =
               Localization.translate_batch(project.id, "es")
    end

    test "returns zero counts when no pending texts exist" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      create_provider_config(project.id)

      # No texts created, so nothing to translate
      # This will try to call DeepL but there are no texts
      assert {:ok, %{translated: 0, failed: 0, errors: []}} =
               Localization.translate_batch(project.id, "es")
    end

    test "translates pending texts in bounded cursor pages without skipping rows" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      create_provider_config(project.id)
      set_fake_translation_recorder()

      for index <- 1..5 do
        localized_text_fixture(project.id, text_attrs(index))
      end

      assert {:ok, %{translated: 5, failed: 0, errors: []}} =
               Localization.translate_batch(project.id, "es",
                 translator: FakeTranslationProvider,
                 batch_size: 2
               )

      assert_received {:fake_translation_provider_call, ["Text 1", "Text 2"]}
      assert_received {:fake_translation_provider_call, ["Text 3", "Text 4"]}
      assert_received {:fake_translation_provider_call, ["Text 5"]}
      refute_received {:fake_translation_provider_call, _texts}

      assert TextCrud.count_texts(project.id, locale_code: "es", status: "pending") == 0
      assert TextCrud.count_texts(project.id, locale_code: "es", status: "draft") == 5
    end

    test "honors total limit while loading only bounded pages" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      create_provider_config(project.id)
      set_fake_translation_recorder()

      for index <- 1..5 do
        localized_text_fixture(project.id, text_attrs(index))
      end

      assert {:ok, %{translated: 3, failed: 0, errors: []}} =
               Localization.translate_batch(project.id, "es",
                 translator: FakeTranslationProvider,
                 batch_size: 2,
                 limit: 3
               )

      assert_received {:fake_translation_provider_call, ["Text 1", "Text 2"]}
      assert_received {:fake_translation_provider_call, ["Text 3"]}
      refute_received {:fake_translation_provider_call, _texts}

      assert TextCrud.count_texts(project.id, locale_code: "es", status: "pending") == 2
      assert TextCrud.count_texts(project.id, locale_code: "es", status: "draft") == 3
    end

    test "reports cumulative progress after each database page" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      create_provider_config(project.id)
      test_pid = self()

      for index <- 1..3 do
        localized_text_fixture(project.id, text_attrs(index))
      end

      assert {:ok, %{translated: 3}} =
               Localization.translate_batch(project.id, "es",
                 translator: FakeTranslationProvider,
                 batch_size: 2,
                 progress_callback: fn result -> send(test_pid, {:progress, result.translated}) end
               )

      assert_received {:progress, 2}
      assert_received {:progress, 3}
    end

    test "stops before loading another page when cancellation is requested" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      create_provider_config(project.id)
      test_pid = self()

      for index <- 1..3 do
        localized_text_fixture(project.id, text_attrs(index))
      end

      assert {:error, :cancelled} =
               Localization.translate_batch(project.id, "es",
                 translator: FakeTranslationProvider,
                 batch_size: 2,
                 cancelled?: fn ->
                   Process.get(:cancel_batch, false)
                 end,
                 progress_callback: fn result ->
                   send(test_pid, {:progress, result.translated})
                   Process.put(:cancel_batch, true)
                 end
               )

      assert_received {:progress, 2}
      assert TextCrud.count_texts(project.id, locale_code: "es", status: "draft") == 2
      assert TextCrud.count_texts(project.id, locale_code: "es", status: "pending") == 1
    end
  end

  describe "translate_single/2" do
    test "returns error when no provider is configured" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:error, :no_provider_configured} =
               Localization.translate_single(project.id, 999)
    end

    test "returns error when text not found" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      create_provider_config(project.id)

      assert {:error, :text_not_found} =
               Localization.translate_single(project.id, 999_999)
    end

    test "returns error when source text is empty" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      create_provider_config(project.id)

      text = localized_text_fixture(project.id, %{source_text: ""})

      assert {:error, :empty_source_text} =
               Localization.translate_single(project.id, text.id)
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp create_provider_config(project_id, opts \\ []) do
    api_key = Keyword.get(opts, :api_key, "test-key-123")

    %ProviderConfig{project_id: project_id}
    |> ProviderConfig.changeset(%{
      "provider" => "deepl",
      "api_key_encrypted" => api_key,
      "api_endpoint" => "https://api-free.deepl.com",
      "is_active" => true
    })
    |> Storyarn.Repo.insert!()
  end

  defp set_fake_translation_recorder do
    Process.put(:fake_translation_provider_test_pid, self())
  end

  defp text_attrs(index) do
    text = "Text #{index}"

    %{
      source_text: text,
      source_text_hash: source_text_hash(text),
      status: "pending"
    }
  end

  defp source_text_hash(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end
end
