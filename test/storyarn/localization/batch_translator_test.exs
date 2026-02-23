defmodule Storyarn.Localization.BatchTranslatorTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Localization

  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

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

    %Storyarn.Localization.ProviderConfig{project_id: project_id}
    |> Storyarn.Localization.ProviderConfig.changeset(%{
      "provider" => "deepl",
      "api_key_encrypted" => api_key,
      "api_endpoint" => "https://api-free.deepl.com",
      "is_active" => true
    })
    |> Storyarn.Repo.insert!()
  end
end
