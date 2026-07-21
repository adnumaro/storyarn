defmodule Storyarn.AI.Providers.DeepLTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Providers.DeepL

  @stub StoryarnTest.AI.DeepL

  test "metadata advertises the expected identifier, URLs, and translation-only capability" do
    metadata = DeepL.metadata()

    assert metadata.id == :deepl
    assert metadata.name == "DeepL"
    assert metadata.key_generation_url =~ "deepl.com"
    assert metadata.docs_url =~ "developers.deepl.com"
    assert metadata.capabilities == [:translation]
  end

  test "validate_key hits /v2/usage on the pro host with DeepL-Auth-Key auth and accepts 200" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.host == "api.deepl.com"
      assert conn.request_path == "/v2/usage"

      assert Plug.Conn.get_req_header(conn, "authorization") ==
               ["DeepL-Auth-Key deepl-pro-valid"]

      Req.Test.json(conn, %{"character_count" => 0, "character_limit" => 500_000})
    end)

    assert {:ok, %{account_email: nil, account_display_name: nil}} =
             DeepL.validate_key("deepl-pro-valid")
  end

  test "validate_key routes keys suffixed :fx to the free host" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.host == "api-free.deepl.com"
      assert conn.request_path == "/v2/usage"

      Req.Test.json(conn, %{"character_count" => 0, "character_limit" => 500_000})
    end)

    assert {:ok, _account_info} = DeepL.validate_key("deepl-free-valid:fx")
  end

  test "validate_key returns :invalid_key on 401" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

    assert {:error, :invalid_key} = DeepL.validate_key("bad")
  end

  test "validate_key returns :invalid_key on 403" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 403, "{}") end)

    assert {:error, :invalid_key} = DeepL.validate_key("forbidden")
  end
end
