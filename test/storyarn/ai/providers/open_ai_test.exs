defmodule Storyarn.AI.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Providers.OpenAI

  @stub StoryarnTest.AI.OpenAI

  describe "metadata/0" do
    test "advertises the expected identifier and console URLs" do
      metadata = OpenAI.metadata()

      assert metadata.id == :openai
      assert metadata.name == "OpenAI"
      assert metadata.key_generation_url =~ "platform.openai.com"
      assert metadata.docs_url =~ "platform.openai.com"
      assert metadata.key_placeholder =~ "sk-"
    end
  end

  describe "validate_key/1" do
    test "returns :ok with nil account info on 200 and sends bearer auth" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/v1/models"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk-proj-valid"]
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, %{account_email: nil, account_display_name: nil}} =
               OpenAI.validate_key("sk-proj-valid")
    end

    test "returns :invalid_key on 401" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 401, ~s({"error": {"code": "invalid_api_key"}}))
      end)

      assert {:error, :invalid_key} = OpenAI.validate_key("sk-proj-bad")
    end

    test "returns :rate_limited on 429" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 429, ~s({"error": {"code": "rate_limit_exceeded"}}))
      end)

      assert {:error, :rate_limited} = OpenAI.validate_key("sk-proj-any")
    end

    test "returns :provider_error on 5xx" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 500, ~s({"error": {"code": "server_error"}}))
      end)

      assert {:error, :provider_error} = OpenAI.validate_key("sk-proj-any")
    end

    test "returns :network_error when the request fails to send" do
      Req.Test.stub(@stub, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :network_error} = OpenAI.validate_key("sk-proj-any")
    end
  end
end
