defmodule Storyarn.AI.IntegrationCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.AI
  alias Storyarn.AI.AuditEntry
  alias Storyarn.AI.Integration
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

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
          connected_at: TimeHelpers.now()
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

  describe "credential maintenance" do
    setup do
      user = user_fixture()

      Req.Test.stub(@stub, fn conn ->
        Req.Test.json(conn, %{"data" => [%{"id" => "claude-old"}]})
      end)

      {:ok, integration} =
        AI.connect(user, :anthropic, "sk-ant-api03-original-abcd")

      old_validated_at = DateTime.add(TimeHelpers.now(), -60, :second)

      integration =
        integration
        |> Ecto.Changeset.change(last_validated_at: old_validated_at)
        |> Repo.update!()

      %{
        user: user,
        integration: integration,
        old_validated_at: old_validated_at
      }
    end

    test "replace validates first and updates the same integration atomically", ctx do
      Req.Test.stub(@stub, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") ==
                 ["sk-ant-api03-replacement-wxyz"]

        Req.Test.json(conn, %{"data" => [%{"id" => "claude-new"}]})
      end)

      assert {:ok, replaced} =
               AI.replace_integration_key(
                 ctx.user,
                 ctx.integration,
                 "sk-ant-api03-replacement-wxyz"
               )

      assert replaced.id == ctx.integration.id
      assert replaced.api_key_encrypted == "sk-ant-api03-replacement-wxyz"
      assert replaced.key_last_four == "wxyz"
      assert replaced.available_models == ["claude-new"]
      assert DateTime.after?(replaced.last_validated_at, ctx.old_validated_at)
      assert Repo.aggregate(Integration, :count) == 1

      assert ["connected", "key_replaced"] ==
               AuditEntry
               |> Repo.all()
               |> Enum.map(& &1.action)

      audit = Repo.get_by!(AuditEntry, action: "key_replaced")
      assert audit.metadata == %{"integration_id" => ctx.integration.id}
    end

    test "a rejected replacement preserves the prior credential and metadata", ctx do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

      assert {:error, :invalid_key} =
               AI.replace_integration_key(
                 ctx.user,
                 ctx.integration,
                 "sk-ant-api03-invalid-wxyz"
               )

      unchanged = Repo.get!(Integration, ctx.integration.id)
      assert unchanged.api_key_encrypted == ctx.integration.api_key_encrypted
      assert unchanged.key_last_four == ctx.integration.key_last_four
      assert unchanged.available_models == ctx.integration.available_models
      assert unchanged.last_validated_at == ctx.old_validated_at
      assert is_nil(unchanged.revoked_at)

      assert ["connected", "validation_failed"] ==
               AuditEntry
               |> Repo.all()
               |> Enum.map(& &1.action)
    end

    test "a slow replacement cannot overwrite a credential changed while it validates", ctx do
      Req.Test.stub(@stub, fn conn ->
        Integration
        |> Repo.get!(ctx.integration.id)
        |> Integration.replace_key_changeset(%{
          api_key_encrypted: "sk-ant-api03-concurrent-race",
          key_last_four: "race",
          available_models: ["claude-concurrent"],
          last_validated_at: TimeHelpers.now()
        })
        |> Repo.update!()

        Req.Test.json(conn, %{"data" => [%{"id" => "claude-slow-response"}]})
      end)

      assert {:error, :integration_changed} =
               AI.replace_integration_key(
                 ctx.user,
                 ctx.integration,
                 "sk-ant-api03-slow-wxyz"
               )

      current = Repo.get!(Integration, ctx.integration.id)
      assert current.api_key_encrypted == "sk-ant-api03-concurrent-race"
      assert current.key_last_four == "race"
      assert current.available_models == ["claude-concurrent"]
      refute Repo.get_by(AuditEntry, action: "key_replaced")
    end

    test "revalidate refreshes metadata with the stored credential but never replaces it", ctx do
      Req.Test.stub(@stub, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") ==
                 ["sk-ant-api03-original-abcd"]

        Req.Test.json(conn, %{"data" => [%{"id" => "claude-refreshed"}]})
      end)

      assert {:ok, revalidated} =
               AI.revalidate_integration(ctx.user, ctx.integration)

      assert revalidated.id == ctx.integration.id
      assert revalidated.api_key_encrypted == ctx.integration.api_key_encrypted
      assert revalidated.key_last_four == ctx.integration.key_last_four
      assert revalidated.available_models == ["claude-refreshed"]
      assert DateTime.after?(revalidated.last_validated_at, ctx.old_validated_at)

      assert ["connected", "revalidated"] ==
               AuditEntry
               |> Repo.all()
               |> Enum.map(& &1.action)
    end

    test "a failed revalidation preserves the previous validation snapshot", ctx do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 429, "{}") end)

      assert {:error, :rate_limited} =
               AI.revalidate_integration(ctx.user, ctx.integration)

      unchanged = Repo.get!(Integration, ctx.integration.id)
      assert unchanged.available_models == ctx.integration.available_models
      assert unchanged.last_validated_at == ctx.old_validated_at
      assert is_nil(unchanged.revoked_at)
      assert %Integration{id: id} = AI.get_active(ctx.user, :anthropic)
      assert id == ctx.integration.id

      assert ["connected", "validation_failed"] ==
               AuditEntry
               |> Repo.all()
               |> Enum.map(& &1.action)
    end

    test "an invalid stored key is auto-revoked", ctx do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

      assert {:error, :invalid_key} =
               AI.revalidate_integration(ctx.user, ctx.integration)

      revoked = Repo.get!(Integration, ctx.integration.id)
      assert %DateTime{} = revoked.revoked_at
      assert is_nil(AI.get_active(ctx.user, :anthropic))

      assert ["connected", "validation_failed", "auto_revoked"] ==
               AuditEntry
               |> Repo.all()
               |> Enum.map(& &1.action)
    end

    test "credential mutations are actor-scoped", ctx do
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               AI.replace_integration_key(
                 other_user,
                 ctx.integration,
                 "sk-ant-api03-foreign-wxyz"
               )

      assert {:error, :unauthorized} =
               AI.revalidate_integration(other_user, ctx.integration)

      unchanged = Repo.get!(Integration, ctx.integration.id)
      assert unchanged.api_key_encrypted == ctx.integration.api_key_encrypted
      assert unchanged.last_validated_at == ctx.old_validated_at
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
