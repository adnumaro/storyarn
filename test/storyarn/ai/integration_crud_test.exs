defmodule Storyarn.AI.IntegrationCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.AI
  alias Storyarn.AI.AuditEntry
  alias Storyarn.AI.Integration
  alias Storyarn.Repo

  @stub StoryarnTest.AI.Anthropic

  describe "connect/3" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "persists an active integration and audits the event on happy path", %{user: user} do
      Req.Test.stub(@stub, fn conn ->
        Req.Test.json(conn, %{"data" => [%{"id" => "claude-test"}]})
      end)

      assert {:ok, %Integration{} = integration} =
               AI.connect(user, :anthropic, "sk-ant-api03-valid-key-abcd")

      assert integration.user_id == user.id
      assert integration.provider == "anthropic"
      assert integration.key_last_four == "abcd"
      assert is_nil(integration.revoked_at)
      assert integration.connected_at
      assert integration.last_validated_at
      assert integration.available_models == ["claude-test"]

      assert [%AuditEntry{action: "connected"}] = Repo.all(AuditEntry)
    end

    test "does not persist an integration and audits the failure on invalid key", %{user: user} do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

      assert {:error, :invalid_key} = AI.connect(user, :anthropic, "sk-ant-bad")
      assert Repo.aggregate(Integration, :count) == 0

      assert [%AuditEntry{action: "validation_failed", metadata: metadata}] = Repo.all(AuditEntry)
      assert metadata == %{"reason" => "invalid_key"}
    end

    test "the partial unique index rejects duplicate active integrations at the DB level", %{
      user: user
    } do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)
      {:ok, _} = AI.connect(user, :anthropic, "sk-ant-api03-first-abcd")

      # Bypasses the pre-check to prove the constraint fires with the exact
      # name normalize_insert_error/1 matches on for the connect race.
      duplicate =
        Integration.connect_changeset(%Integration{}, %{
          user_id: user.id,
          provider: "anthropic",
          api_key_encrypted: "sk-ant-api03-second-wxyz",
          key_last_four: "wxyz",
          connected_at: Storyarn.Shared.TimeHelpers.now()
        })

      assert {:error, changeset} = Repo.insert(duplicate)

      assert Enum.any?(changeset.errors, fn {_field, {_msg, opts}} ->
               opts[:constraint_name] == "ai_integrations_user_provider_active_index"
             end)
    end

    test "refuses reuse when the user already has an active integration", %{user: user} do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

      assert {:ok, _} = AI.connect(user, :anthropic, "sk-ant-api03-first-abcd")
      assert {:error, :already_connected} = AI.connect(user, :anthropic, "sk-ant-api03-second-wxyz")

      assert Repo.aggregate(Integration, :count) == 1
    end

    test "allows connecting after a prior integration was revoked", %{user: user} do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

      {:ok, integration} = AI.connect(user, :anthropic, "sk-ant-api03-first-abcd")
      {:ok, _} = AI.revoke(user, integration)

      assert {:ok, %Integration{key_last_four: "wxyz"}} =
               AI.connect(user, :anthropic, "sk-ant-api03-second-wxyz")

      assert Repo.aggregate(Integration, :count) == 2
    end

    test "rejects unknown providers", %{user: user} do
      assert {:error, :unknown_provider} = AI.connect(user, :fictional, "whatever")
    end
  end

  describe "revoke/2" do
    setup do
      user = user_fixture()
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)
      {:ok, integration} = AI.connect(user, :anthropic, "sk-ant-api03-valid-abcd")
      %{user: user, integration: integration}
    end

    test "sets revoked_at and audits", %{user: user, integration: integration} do
      assert {:ok, %Integration{revoked_at: %DateTime{}}} = AI.revoke(user, integration)
      assert [_connected, %AuditEntry{action: "disconnected"}] = Repo.all(AuditEntry)
    end

    test "get_active returns nil after revoke", %{user: user, integration: integration} do
      {:ok, _} = AI.revoke(user, integration)
      assert is_nil(AI.get_active(user, :anthropic))
    end

    test "a second revoke is rejected and writes no extra audit", %{user: user, integration: integration} do
      {:ok, _} = AI.revoke(user, integration)

      assert {:error, :already_revoked} = AI.revoke(user, integration)

      disconnected_count =
        AuditEntry
        |> Repo.all()
        |> Enum.count(&(&1.action == "disconnected"))

      assert disconnected_count == 1
    end

    test "another user cannot revoke the integration", %{integration: integration} do
      other_user = user_fixture()

      assert {:error, :unauthorized} = AI.revoke(other_user, integration)
      assert is_nil(Repo.get!(Integration, integration.id).revoked_at)
    end
  end

  describe "list_active/1" do
    test "returns only active integrations for the given user" do
      user_a = user_fixture()
      user_b = user_fixture()
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

      {:ok, _} = AI.connect(user_a, :anthropic, "sk-ant-api03-user-a-key1")
      {:ok, other_integration} = AI.connect(user_b, :anthropic, "sk-ant-api03-user-b-key2")
      {:ok, _revoked} = AI.revoke(user_b, other_integration)

      assert [%Integration{user_id: user_a_id}] = AI.list_active(user_a)
      assert user_a_id == user_a.id
      assert AI.list_active(user_b) == []
    end
  end

  describe "Inspect protocol" do
    test "redacts the encrypted key" do
      integration = %Integration{
        api_key_encrypted: "sensitive-ciphertext",
        provider: "anthropic",
        key_last_four: "abcd"
      }

      inspected = inspect(integration)

      refute inspected =~ "sensitive-ciphertext"
      assert inspected =~ "abcd"
    end
  end
end
