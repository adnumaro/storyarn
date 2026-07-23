defmodule Storyarn.AI.RuntimeTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.AI
  alias Storyarn.AI.AuditEntry
  alias Storyarn.AI.Integration
  alias Storyarn.Repo

  @stub StoryarnTest.AI.Anthropic
  @plaintext_key "sk-ant-api03-runtime-abcd"

  setup do
    user = user_fixture()
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)
    {:ok, integration} = AI.connect(user, :anthropic, @plaintext_key)
    %{user: user, integration: integration}
  end

  test "returns :not_connected when the user has no active integration" do
    other_user = user_fixture()

    assert {:error, :not_connected} =
             AI.with_personal_integration(other_user, :anthropic, fn _key -> {:ok, :unused} end)
  end

  test "runs fun with the decrypted plaintext key and passes the result through", %{user: user} do
    assert {:ok, received_key} =
             AI.with_personal_integration(user, :anthropic, fn key -> {:ok, key} end)

    assert received_key == @plaintext_key
  end

  test "touches last_used_at on success", %{user: user, integration: integration} do
    assert is_nil(integration.last_used_at)

    {:ok, _} = AI.with_personal_integration(user, :anthropic, fn _key -> {:ok, :done} end)

    assert %Integration{last_used_at: %DateTime{}} = Repo.get(Integration, integration.id)
  end

  test "auto-revokes and audits when fun reports :unauthorized", %{
    user: user,
    integration: integration
  } do
    assert {:error, :unauthorized} =
             AI.with_personal_integration(user, :anthropic, fn _key -> {:error, :unauthorized} end)

    reloaded = Repo.get(Integration, integration.id)
    assert %DateTime{} = reloaded.revoked_at
    assert is_nil(AI.get_active(user, :anthropic))

    actions = AuditEntry |> Repo.all() |> Enum.map(& &1.action)
    assert "auto_revoked" in actions
  end

  test "repeated unauthorized outcomes never produce a second auto_revoked audit", %{
    user: user,
    integration: integration
  } do
    alias Storyarn.AI.IntegrationCrud

    {:error, :unauthorized} =
      AI.with_personal_integration(user, :anthropic, fn _key -> {:error, :unauthorized} end)

    # The integration is now revoked, so a second call cannot even start...
    assert {:error, :not_connected} =
             AI.with_personal_integration(user, :anthropic, fn _key -> {:error, :unauthorized} end)

    # ...and even a direct conditional revoke (the concurrent-loser path)
    # cannot write another lifecycle event.
    assert {:error, :already_revoked} = IntegrationCrud.revoke_active(integration, :auto_revoked)

    auto_revoked_count =
      AuditEntry
      |> Repo.all()
      |> Enum.count(&(&1.action == "auto_revoked"))

    assert auto_revoked_count == 1
  end

  test "passes other errors through without revoking or touching usage", %{
    user: user,
    integration: integration
  } do
    assert {:error, :timeout} =
             AI.with_personal_integration(user, :anthropic, fn _key -> {:error, :timeout} end)

    reloaded = Repo.get(Integration, integration.id)
    assert is_nil(reloaded.revoked_at)
    assert is_nil(reloaded.last_used_at)
  end

  test "emits telemetry start and stop events", %{user: user} do
    ref = make_ref()
    test_pid = self()

    :telemetry.attach_many(
      "runtime-test-#{inspect(ref)}",
      [[:ai, :integration, :call, :start], [:ai, :integration, :call, :stop]],
      fn event, _measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach("runtime-test-#{inspect(ref)}") end)

    {:ok, _} = AI.with_personal_integration(user, :anthropic, fn _key -> {:ok, :done} end)

    assert_receive {:telemetry, [:ai, :integration, :call, :start],
                    %{provider: "anthropic", credential_kind: "personal_byok"} = start_metadata}

    assert_receive {:telemetry, [:ai, :integration, :call, :stop],
                    %{provider: "anthropic", credential_kind: "personal_byok"} = stop_metadata}

    refute Map.has_key?(start_metadata, :user_id)
    refute Map.has_key?(stop_metadata, :user_id)
  end
end
