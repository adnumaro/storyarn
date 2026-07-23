defmodule Storyarn.AI.InferenceProviders.FireworksTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.InferenceProviders.Fireworks
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.ResolvedCredential

  @stub StoryarnTest.AI.Fireworks

  test "uses Fireworks chat completions with structured output and persisted pricing" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/inference/v1/chat/completions"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer fireworks-secret"]

      {:ok, encoded, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(encoded)

      assert body["model"] == "accounts/fireworks/models/test-model"

      assert body["response_format"] == %{
               "type" => "json_schema",
               "json_schema" => %{
                 "name" => "diagnostic",
                 "schema" => response_schema()
               }
             }

      Req.Test.json(conn, %{
        "id" => "fireworks-request-123",
        "choices" => [%{"message" => %{"content" => ~s({"status":"ok"})}}],
        "usage" => %{"prompt_tokens" => 2_000, "completion_tokens" => 250}
      })
    end)

    assert {:ok, response} = Fireworks.generate(credential(), request())
    assert response.output == %{"status" => "ok"}
    assert response.provider_request_id == "fireworks-request-123"
    assert response.input_units == 2_000
    assert response.output_units == 250
    assert response.provider_cost_currency == "USD"
    assert Decimal.equal?(response.provider_cost, Decimal.new("0.0035"))
  end

  test "fails closed when the persisted route lacks no-training provenance" do
    request = update_in(request().provider_configuration, &Map.delete(&1, "training_usage"))

    assert {:error, :provider_error} = Fireworks.generate(credential(), request)
  end

  test "does not call the provider for contextual input without a curated model contract" do
    request = %{request() | input: contextual_input(), contextual?: true}

    assert {:error, :model_context_limits_unavailable} =
             Fireworks.generate(credential(), request)
  end

  test "rejects atom and string protected request overrides before provider access" do
    for overrides <- [%{max_tokens: 1}, %{"messages" => []}] do
      with_request_overrides(overrides, fn ->
        assert {:error, :provider_error} = Fireworks.generate(credential(), request())
      end)
    end
  end

  test "validates allowed overrides as part of the exact body sent to the provider" do
    request = %{
      request()
      | model: "accounts/fireworks/models/qwen3p7-plus",
        input: contextual_input(),
        contextual?: true
    }

    with_default_catalog(fn ->
      with_request_overrides(%{metadata: String.duplicate("x", 262_144)}, fn ->
        assert {:error, :model_context_window_exceeded} =
                 Fireworks.generate(credential(), request)
      end)
    end)
  end

  test "does not follow provider redirects with the managed credential" do
    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "https://untrusted.test/collect")
      |> Plug.Conn.resp(307, "")
    end)

    assert {:error, :provider_error} = Fireworks.generate(credential(), request())
  end

  defp credential, do: %ResolvedCredential{kind: :managed, value: "fireworks-secret"}

  defp request do
    %{
      task_id: "operator.managed_diagnostic",
      model: "accounts/fireworks/models/test-model",
      input: %{"probe" => "storyarn-managed-ai-diagnostic-v1"},
      contextual?: false,
      max_output_bytes: 256,
      provider_options: %{
        system_prompt: "Return JSON.",
        schema_name: "diagnostic",
        response_schema: response_schema(),
        max_output_tokens: 32,
        temperature: 0
      },
      provider_configuration: %{
        "region" => "global",
        "data_retention" => "zero_data_retention",
        "training_usage" => "disabled",
        "provider_price" => %{
          "version" => 1,
          "currency" => "USD",
          "input_per_million" => "1.5",
          "output_per_million" => "2.0",
          "max_estimated_cost" => "0.01"
        }
      }
    }
  end

  defp response_schema do
    %{
      "type" => "object",
      "properties" => %{"status" => %{"type" => "string"}},
      "required" => ["status"],
      "additionalProperties" => false
    }
  end

  defp contextual_input do
    %{
      "request" => %{"probe" => "storyarn-managed-ai-diagnostic-v1"},
      "context" => %{
        "version" => "storyarn-context-v1",
        "scope" => "sheet",
        "entities" => []
      }
    }
  end

  defp with_request_overrides(overrides, callback) do
    original = Application.fetch_env!(:storyarn, Fireworks)
    Application.put_env(:storyarn, Fireworks, Keyword.put(original, :request_overrides, overrides))

    try do
      callback.()
    after
      Application.put_env(:storyarn, Fireworks, original)
    end
  end

  defp with_default_catalog(callback) do
    original = Application.fetch_env(:storyarn, ModelCatalog)
    Application.delete_env(:storyarn, ModelCatalog)

    try do
      callback.()
    after
      case original do
        {:ok, config} -> Application.put_env(:storyarn, ModelCatalog, config)
        :error -> Application.delete_env(:storyarn, ModelCatalog)
      end
    end
  end
end
