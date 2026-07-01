defmodule Storyarn.Localization.Providers.DeepLTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Providers.DeepL

  describe "api endpoint validation" do
    test "resolves blank and supported endpoints safely" do
      assert ProviderConfig.api_endpoint_or_default(nil) ==
               {:ok, ProviderConfig.default_api_endpoint()}

      assert ProviderConfig.api_endpoint_or_default("") ==
               {:ok, ProviderConfig.default_api_endpoint()}

      assert ProviderConfig.api_endpoint_or_default(" https://api-free.deepl.com/ ") ==
               {:ok, "https://api-free.deepl.com"}

      assert ProviderConfig.api_endpoint_or_default("https://api.deepl.com/") ==
               {:ok, "https://api.deepl.com"}
    end

    test "rejects unsupported stored endpoints before making requests" do
      config = %ProviderConfig{
        api_key_encrypted: "secret",
        api_endpoint: "https://attacker.example",
        deepl_glossary_ids: %{}
      }

      assert DeepL.get_usage(config) == {:error, :unsupported_api_endpoint}
      assert DeepL.supported_languages(config) == {:error, :unsupported_api_endpoint}
      assert DeepL.translate(["hello"], "en", "es", config) == {:error, :unsupported_api_endpoint}

      assert DeepL.create_glossary("test", "en", "es", [], config) ==
               {:error, :unsupported_api_endpoint}

      assert DeepL.delete_glossary("glossary-id", config) == {:error, :unsupported_api_endpoint}
    end
  end
end
