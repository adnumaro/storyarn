defmodule Storyarn.AI.Providers.MoonshotTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Providers.Moonshot

  @stub StoryarnTest.AI.Moonshot

  test "metadata advertises the expected identifier and console URLs" do
    metadata = Moonshot.metadata()

    assert metadata.id == :moonshot
    assert metadata.name == "Kimi (Moonshot)"
    assert metadata.key_generation_url =~ "platform.moonshot.ai"
    assert metadata.docs_url =~ "platform.moonshot.ai"
  end

  test "validate_key hits /v1/models with bearer auth and accepts 200" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/v1/models"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk-moonshot-valid"]
      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, %{account_email: nil, account_display_name: nil}} =
             Moonshot.validate_key("sk-moonshot-valid")
  end

  test "validate_key returns :invalid_key on 401" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

    assert {:error, :invalid_key} = Moonshot.validate_key("sk-bad")
  end
end
