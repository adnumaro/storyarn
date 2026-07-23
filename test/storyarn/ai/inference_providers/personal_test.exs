defmodule Storyarn.AI.InferenceProviders.PersonalTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.InferenceProviders.Personal.Anthropic
  alias Storyarn.AI.InferenceProviders.Personal.OpenAI
  alias Storyarn.AI.ResolvedCredential

  @openai_stub StoryarnTest.AI.PersonalOpenAI
  @anthropic_stub StoryarnTest.AI.PersonalAnthropic

  test "OpenAI sends structured output without storage and returns content-free usage" do
    Req.Test.stub(@openai_stub, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer personal-openai-key"]
      {:ok, encoded, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(encoded)

      assert body["store"] == false
      assert body["response_format"]["type"] == "json_schema"
      assert body["response_format"]["json_schema"]["name"] == "personal_contract"
      assert body["response_format"]["json_schema"]["schema"] == schema()

      Req.Test.json(conn, %{
        "id" => "openai-personal-request",
        "choices" => [%{"message" => %{"content" => ~s({"status":"ok"})}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 4}
      })
    end)

    assert {:ok, response} = OpenAI.generate(personal_credential("personal-openai-key"), request())
    assert response.output == %{"status" => "ok"}
    assert response.provider_request_id == "openai-personal-request"
    assert response.input_units == 10
    assert response.output_units == 4
    refute Map.has_key?(response, :provider_cost)
    refute Map.has_key?(response, :provider_cost_currency)
  end

  test "OpenAI classifies authentication separately and does not follow redirects" do
    Req.Test.stub(@openai_stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

    assert {:error, :unauthorized} =
             OpenAI.generate(personal_credential("invalid"), request())

    Req.Test.stub(@openai_stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "https://untrusted.test/collect")
      |> Plug.Conn.resp(307, "")
    end)

    assert {:error, :provider_error} =
             OpenAI.generate(personal_credential("personal-openai-key"), request())
  end

  test "Anthropic uses the current output_config format and actor-owned key" do
    Req.Test.stub(@anthropic_stub, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["personal-anthropic-key"]
      assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]
      {:ok, encoded, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(encoded)

      assert body["output_config"] == %{
               "format" => %{"type" => "json_schema", "schema" => schema()}
             }

      Req.Test.json(conn, %{
        "id" => "anthropic-personal-request",
        "content" => [%{"type" => "text", "text" => ~s({"status":"ok"})}],
        "usage" => %{"input_tokens" => 11, "output_tokens" => 5}
      })
    end)

    assert {:ok, response} =
             Anthropic.generate(
               personal_credential("personal-anthropic-key"),
               request("personal-anthropic-model")
             )

    assert response.output == %{"status" => "ok"}
    assert response.provider_request_id == "anthropic-personal-request"
    assert response.input_units == 11
    assert response.output_units == 5
    refute Map.has_key?(response, :provider_cost)
  end

  test "provider 403 is not misclassified as an invalid personal credential" do
    Req.Test.stub(@anthropic_stub, fn conn -> Plug.Conn.resp(conn, 403, "{}") end)

    assert {:error, :provider_error} =
             Anthropic.generate(
               personal_credential("personal-anthropic-key"),
               request("personal-anthropic-model")
             )
  end

  defp personal_credential(value), do: %ResolvedCredential{kind: :personal_byok, value: value}

  defp request(model \\ "personal-openai-model") do
    %{
      task_id: "contract.personal",
      model: model,
      input: %{"text" => "private content"},
      max_output_bytes: 1_024,
      provider_options: %{
        system_prompt: "Return JSON.",
        schema_name: "personal_contract",
        response_schema: schema(),
        max_output_tokens: 64,
        temperature: 0
      },
      provider_configuration: %{
        "personal_consent_id" => 123,
        "personal_consent_version" => "personal-egress-v1",
        "response_mode" => "json_schema"
      }
    }
  end

  defp schema do
    %{
      "type" => "object",
      "properties" => %{"status" => %{"type" => "string"}},
      "required" => ["status"],
      "additionalProperties" => false
    }
  end
end
