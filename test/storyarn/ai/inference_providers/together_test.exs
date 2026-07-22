defmodule Storyarn.AI.InferenceProviders.TogetherTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.InferenceProviders.Together
  alias Storyarn.AI.ResolvedCredential

  @stub StoryarnTest.AI.Together

  test "uses structured output, bearer auth and the persisted price snapshot" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/v1/chat/completions"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer managed-secret"]
      {:ok, encoded, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(encoded)
      assert body["model"] == "eu-model-v1"
      assert body["response_format"]["type"] == "json_schema"
      assert body["response_format"]["json_schema"]["schema"]["additionalProperties"] == false

      Req.Test.json(conn, %{
        "id" => "request-123",
        "choices" => [%{"message" => %{"content" => ~s({"status":"ok"})}}],
        "usage" => %{"prompt_tokens" => 1_000, "completion_tokens" => 500}
      })
    end)

    assert {:ok, response} = Together.generate(credential(), request())
    assert response.output == %{"status" => "ok"}
    assert response.provider_request_id == "request-123"
    assert response.input_units == 1_000
    assert response.output_units == 500
    assert response.provider_cost_currency == "USD"
    assert Decimal.equal?(response.provider_cost, Decimal.new("0.0025"))
  end

  test "classifies authentication, rate limiting and uncertain transport outcomes" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)
    assert {:error, :unauthorized} = Together.generate(credential(), request())

    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 429, "{}") end)
    assert {:error, :rate_limited} = Together.generate(credential(), request())

    Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, {:unknown, :transport_outcome_unproven}} = Together.generate(credential(), request())
  end

  test "rejects malformed structured output" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "id" => "request-invalid",
        "choices" => [%{"message" => %{"content" => "not-json"}}],
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
      })
    end)

    assert {:error, :invalid_output} = Together.generate(credential(), request())
  end

  defp credential, do: %ResolvedCredential{kind: :managed, value: "managed-secret"}

  defp request do
    %{
      task_id: "operator.managed_diagnostic",
      model: "eu-model-v1",
      input: %{"probe" => "storyarn-managed-ai-diagnostic-v1"},
      max_output_bytes: 256,
      provider_options: %{
        system_prompt: "Return JSON.",
        schema_name: "diagnostic",
        response_schema: %{
          "type" => "object",
          "properties" => %{"status" => %{"type" => "string"}},
          "required" => ["status"],
          "additionalProperties" => false
        },
        max_output_tokens: 32,
        temperature: 0
      },
      provider_configuration: %{
        "endpoint" => "https://eu.together.test/v1/chat/completions",
        "region" => "eu-test",
        "data_retention" => "zero_data_retention",
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
end
