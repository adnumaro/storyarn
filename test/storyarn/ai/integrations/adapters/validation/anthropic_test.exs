defmodule Storyarn.AI.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Providers.Anthropic

  @stub StoryarnTest.AI.Anthropic

  describe "metadata/0" do
    test "advertises the expected identifier and console URLs" do
      metadata = Anthropic.metadata()

      assert metadata.id == :anthropic
      assert metadata.name == "Anthropic Claude"
      assert metadata.key_generation_url =~ "platform.claude.com"
      assert metadata.docs_url =~ "docs.claude.com"
      assert metadata.key_placeholder =~ "sk-ant-"
    end
  end

  describe "validate_key/1" do
    test "returns :ok with nil account info on 200" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/v1/models"
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["sk-ant-valid"]
        assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, %{account_email: nil, account_display_name: nil}} =
               Anthropic.validate_key("sk-ant-valid")
    end

    test "returns :invalid_key on 401" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 401, ~s({"error": "invalid_api_key"}))
      end)

      assert {:error, :invalid_key} = Anthropic.validate_key("sk-ant-bad")
    end

    test "returns :invalid_key on 403" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 403, ~s({"error": "forbidden"}))
      end)

      assert {:error, :invalid_key} = Anthropic.validate_key("sk-ant-bad")
    end

    test "returns :rate_limited on 429" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 429, ~s({"error": "rate_limited"}))
      end)

      assert {:error, :rate_limited} = Anthropic.validate_key("sk-ant-any")
    end

    test "returns :provider_error on 5xx" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 503, ~s({"error": "unavailable"}))
      end)

      assert {:error, :provider_error} = Anthropic.validate_key("sk-ant-any")
    end

    test "returns :network_error when the request fails to send" do
      Req.Test.stub(@stub, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :network_error} = Anthropic.validate_key("sk-ant-any")
    end

    test "returns {:unexpected_status, code} on unhandled statuses" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 418, ~s({"error": "teapot"}))
      end)

      assert {:error, {:unexpected_status, 418}} = Anthropic.validate_key("sk-ant-any")
    end
  end
end
