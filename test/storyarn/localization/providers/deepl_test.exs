defmodule Storyarn.Localization.Providers.DeepLTest do
  use ExUnit.Case, async: false

  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Providers.DeepL

  setup do
    Req.Test.verify_on_exit!()

    Application.put_env(:storyarn, :deepl_req_options,
      plug: {Req.Test, __MODULE__},
      retry: false
    )

    on_exit(fn -> Application.delete_env(:storyarn, :deepl_req_options) end)
    :ok
  end

  describe "translate/5 HTTP contract" do
    test "protects placeholders in plain text and restores them in the response" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/v2/translate"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["DeepL-Auth-Key secret"]

        {body, conn} = read_json(conn)
        assert body["source_lang"] == "EN"
        assert body["target_lang"] == "ES"
        assert body["tag_handling"] == "html"
        assert body["text"] == [~s(Hello <span translate="no">{name}</span>)]

        Req.Test.json(conn, %{
          translations: [
            %{text: ~s(Hola <span translate="no">{name}</span>), detected_source_language: "EN"}
          ]
        })
      end)

      assert {:ok, [%{text: "Hola {name}", detected_source_lang: "EN"}]} =
               DeepL.translate(["Hello {name}"], "en", "es", config())
    end

    test "splits requests at fifty texts while preserving order" do
      Req.Test.stub(__MODULE__, fn conn ->
        {body, conn} = read_json(conn)
        send(self(), {:request_size, length(body["text"])})

        translations = Enum.map(body["text"], &%{text: "translated:#{&1}", detected_source_language: "EN"})
        Req.Test.json(conn, %{translations: translations})
      end)

      texts = Enum.map(1..51, &"text-#{&1}")

      assert {:ok, translations} = DeepL.translate(texts, "en", "es", config())
      assert Enum.map(translations, & &1.text) == Enum.map(texts, &"translated:#{&1}")
      assert_receive {:request_size, 50}
      assert_receive {:request_size, 1}
    end

    test "splits requests before the encoded body reaches the safety limit" do
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {raw_body, conn} = read_raw_body(conn)
        send(test_pid, {:body_size, byte_size(raw_body)})
        body = Jason.decode!(raw_body)
        translations = Enum.map(body["text"], &%{text: &1, detected_source_language: "EN"})
        Req.Test.json(conn, %{translations: translations})
      end)

      texts = [String.duplicate("a", 70_000), String.duplicate("b", 70_000)]

      assert {:ok, translations} = DeepL.translate(texts, "en", "es", config())
      assert length(translations) == 2
      assert_receive {:body_size, first_size}
      assert_receive {:body_size, second_size}
      assert first_size < 128 * 1024
      assert second_size < 128 * 1024
    end

    test "rejects a single oversized text without making a request" do
      Req.Test.stub(__MODULE__, fn _conn -> flunk("request should not be sent") end)

      assert {:error, {:text_too_large, 0}} =
               DeepL.translate([String.duplicate("a", 125_000)], "en", "es", config())
    end

    test "rejects a provider response that loses a placeholder" do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{translations: [%{text: "Hola", detected_source_language: "EN"}]})
      end)

      assert {:error, {:placeholder_mismatch, 0, %{missing: ["{name}"], extra: []}}} =
               DeepL.translate(["Hello {name}"], "en", "es", config())
    end

    test "maps rate limit, quota and authentication responses" do
      for {status, expected} <- [{429, :rate_limited}, {456, :quota_exceeded}, {403, :invalid_api_key}] do
        Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, status, "") end)
        assert DeepL.translate(["Hello"], "en", "es", config()) == {:error, expected}
      end
    end
  end

  describe "glossary v3 contract" do
    test "creates a glossary with a dictionary payload" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/v3/glossaries"
        {body, conn} = read_json(conn)

        assert body == %{
                 "name" => "Storyarn es",
                 "dictionaries" => [
                   %{
                     "source_lang" => "en",
                     "target_lang" => "es",
                     "entries" => "sword\tespada",
                     "entries_format" => "tsv"
                   }
                 ]
               }

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{glossary_id: "glossary-1"})
      end)

      assert DeepL.create_glossary("Storyarn es", "en-US", "es", [{"sword", "espada"}], config()) ==
               {:ok, "glossary-1"}
    end

    test "deletes v3 glossaries idempotently" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/v3/glossaries/glossary-1"
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert DeepL.delete_glossary("glossary-1", config()) == :ok
    end
  end

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

  defp config do
    %ProviderConfig{
      api_key_encrypted: "secret",
      api_endpoint: ProviderConfig.default_api_endpoint(),
      deepl_glossary_ids: %{},
      settings: %{}
    }
  end

  defp read_json(conn) do
    {body, conn} = read_raw_body(conn)
    {Jason.decode!(body), conn}
  end

  defp read_raw_body(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {body, conn}
  end
end
