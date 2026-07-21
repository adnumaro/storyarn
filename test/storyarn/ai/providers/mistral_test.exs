defmodule Storyarn.AI.Providers.MistralTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Providers.Mistral

  @stub StoryarnTest.AI.Mistral

  test "metadata advertises the expected identifier and console URLs" do
    metadata = Mistral.metadata()

    assert metadata.id == :mistral
    assert metadata.name == "Mistral"
    assert metadata.key_generation_url =~ "console.mistral.ai"
    assert metadata.docs_url =~ "docs.mistral.ai"
  end

  test "validate_key hits /v1/models with bearer auth and accepts 200" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/v1/models"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer mistral-valid"]
      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, %{account_email: nil, account_display_name: nil}} =
             Mistral.validate_key("mistral-valid")
  end

  test "validate_key returns :invalid_key on 401" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

    assert {:error, :invalid_key} = Mistral.validate_key("bad")
  end
end
