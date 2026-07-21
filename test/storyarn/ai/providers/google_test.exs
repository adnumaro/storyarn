defmodule Storyarn.AI.Providers.GoogleTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Providers.Google

  @stub StoryarnTest.AI.Google

  describe "metadata/0" do
    test "advertises the expected identifier and console URLs" do
      metadata = Google.metadata()

      assert metadata.id == :google
      assert metadata.name == "Google Gemini"
      assert metadata.key_generation_url =~ "aistudio.google.com"
      assert metadata.docs_url =~ "ai.google.dev"
      assert metadata.key_placeholder =~ "AIza"
    end
  end

  describe "validate_key/1" do
    test "returns :ok on 200 and authenticates via x-goog-api-key header (no key in URL)" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/v1beta/models"
        assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["AIza-valid"]
        assert conn.query_string == ""
        Req.Test.json(conn, %{"models" => []})
      end)

      assert {:ok, %{account_email: nil, account_display_name: nil}} =
               Google.validate_key("AIza-valid")
    end

    test "returns :invalid_key on 400 (Google's API_KEY_INVALID status)" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 400, ~s({"error": {"status": "INVALID_ARGUMENT"}}))
      end)

      assert {:error, :invalid_key} = Google.validate_key("AIza-bad")
    end

    test "returns :invalid_key on 403" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 403, ~s({"error": {"status": "PERMISSION_DENIED"}}))
      end)

      assert {:error, :invalid_key} = Google.validate_key("AIza-bad")
    end

    test "returns :rate_limited on 429" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 429, ~s({"error": {"status": "RESOURCE_EXHAUSTED"}}))
      end)

      assert {:error, :rate_limited} = Google.validate_key("AIza-any")
    end

    test "returns :provider_error on 5xx" do
      Req.Test.stub(@stub, fn conn ->
        Plug.Conn.resp(conn, 500, ~s({"error": {"status": "INTERNAL"}}))
      end)

      assert {:error, :provider_error} = Google.validate_key("AIza-any")
    end

    test "returns :network_error when the request fails to send" do
      Req.Test.stub(@stub, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :network_error} = Google.validate_key("AIza-any")
    end
  end
end
