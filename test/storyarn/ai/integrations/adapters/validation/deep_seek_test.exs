defmodule Storyarn.AI.Providers.DeepSeekTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Providers.DeepSeek

  @stub StoryarnTest.AI.DeepSeek

  test "metadata advertises the expected identifier and console URLs" do
    metadata = DeepSeek.metadata()

    assert metadata.id == :deepseek
    assert metadata.name == "DeepSeek"
    assert metadata.key_generation_url =~ "platform.deepseek.com"
    assert metadata.docs_url =~ "api-docs.deepseek.com"
  end

  test "validate_key hits /models (no /v1 prefix) with bearer auth and accepts 200" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/models"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk-deepseek-valid"]
      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, %{account_email: nil, account_display_name: nil}} =
             DeepSeek.validate_key("sk-deepseek-valid")
  end

  test "validate_key returns :invalid_key on 401" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

    assert {:error, :invalid_key} = DeepSeek.validate_key("sk-bad")
  end
end
