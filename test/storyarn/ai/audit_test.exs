defmodule Storyarn.AI.AuditTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Audit
  alias Storyarn.AI.AuditEntry
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  describe "sanitize_metadata/1" do
    test "keeps only whitelisted scalar keys" do
      input = %{
        reason: "invalid_key",
        unexpected_status: 418,
        integration_id: 7,
        workspace_id: 11,
        assignment_id: 13,
        api_key: "sk-ant-leaked-secret",
        nested: %{api_key: "sk-deeper-leak"}
      }

      sanitized = Audit.sanitize_metadata(input)

      assert sanitized == %{
               "reason" => "invalid_key",
               "unexpected_status" => 418,
               "integration_id" => 7,
               "workspace_id" => 11,
               "assignment_id" => 13
             }

      refute inspect(sanitized) =~ "leak"
    end

    test "accepts string keys from JSON-shaped input" do
      assert Audit.sanitize_metadata(%{"reason" => "network_error", "api_key" => "sk-leak"}) ==
               %{"reason" => "network_error"}
    end

    test "drops oversized and non-scalar values" do
      assert Audit.sanitize_metadata(%{reason: String.duplicate("x", 300)}) == %{}
      assert Audit.sanitize_metadata(%{reason: %{deep: "map"}}) == %{}
      assert Audit.sanitize_metadata(%{reason: [1, 2]}) == %{}
    end

    test "atom values are stringified" do
      assert Audit.sanitize_metadata(%{reason: :invalid_key}) == %{"reason" => "invalid_key"}
    end

    test "non-map input becomes an empty map" do
      assert Audit.sanitize_metadata(nil) == %{}
      assert Audit.sanitize_metadata("string") == %{}
    end
  end

  describe "log/4" do
    setup do
      %{user: user_fixture()}
    end

    test "persists actor_id alongside the nilifiable FK", %{user: user} do
      assert {:ok, entry} = Audit.log(user.id, :anthropic, :connected, %{})
      assert entry.user_id == user.id
      assert entry.actor_id == user.id
    end

    test "forbidden metadata keys never reach the database", %{user: user} do
      {:ok, entry} = Audit.log(user.id, :anthropic, :connected, %{api_key: "sk-secret"})

      assert Repo.get(AuditEntry, entry.id).metadata == %{}
    end
  end

  describe "append-only enforcement" do
    setup do
      user = user_fixture()
      {:ok, entry} = Audit.log(user.id, :anthropic, :connected, %{})
      %{user: user, entry: entry}
    end

    test "database trigger blocks UPDATE", %{entry: entry} do
      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.update_all(
          from(a in AuditEntry, where: a.id == ^entry.id),
          set: [action: "disconnected"]
        )
      end
    end

    test "database trigger blocks DELETE", %{entry: entry} do
      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.delete(entry)
      end
    end

    test "database trigger rejects a forged user-link nilification", %{entry: entry} do
      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.query!("UPDATE ai_integration_audits SET user_id = NULL WHERE id = $1", [entry.id])
      end
    end

    test "trigger function uses a fixed safe search path" do
      result =
        Repo.query!("""
        SELECT proconfig
        FROM pg_proc
        WHERE oid = 'public.ai_integration_audits_append_only()'::regprocedure
        """)

      assert [[settings]] = result.rows
      assert "search_path=pg_catalog, pg_temp" in settings
    end

    test "a nested non-FK trigger cannot forge nilification or rewrite the row identity", %{
      user: user,
      entry: entry
    } do
      Repo.query!("CREATE TEMP TABLE ai_audit_nilify_probe (audit_id bigint NOT NULL) ON COMMIT DROP")

      Repo.query!("""
      CREATE FUNCTION pg_temp.forge_ai_audit_nilification() RETURNS trigger AS $$
      BEGIN
        UPDATE ai_integration_audits
        SET id = id + 1000000, user_id = NULL
        WHERE id = NEW.audit_id;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """)

      Repo.query!("""
      CREATE TRIGGER forge_ai_audit_nilification_trigger
      AFTER INSERT ON ai_audit_nilify_probe
      FOR EACH ROW EXECUTE FUNCTION pg_temp.forge_ai_audit_nilification();
      """)

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.transaction(fn ->
          Repo.query!("INSERT INTO ai_audit_nilify_probe (audit_id) VALUES ($1)", [entry.id])
        end)
      end

      assert Repo.get!(AuditEntry, entry.id).user_id == user.id
    end

    test "a temporary users table cannot forge nested nilification", %{
      user: user,
      entry: entry
    } do
      Repo.query!("CREATE TEMP TABLE users (id bigint PRIMARY KEY) ON COMMIT DROP")
      Repo.query!("CREATE TEMP TABLE ai_audit_shadow_probe (audit_id bigint NOT NULL) ON COMMIT DROP")

      Repo.query!("""
      CREATE FUNCTION pg_temp.forge_ai_audit_shadow_nilification() RETURNS trigger AS $$
      BEGIN
        UPDATE public.ai_integration_audits
        SET user_id = NULL
        WHERE id = NEW.audit_id;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """)

      Repo.query!("""
      CREATE TRIGGER forge_ai_audit_shadow_nilification_trigger
      AFTER INSERT ON ai_audit_shadow_probe
      FOR EACH ROW EXECUTE FUNCTION pg_temp.forge_ai_audit_shadow_nilification();
      """)

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.transaction(fn ->
          Repo.query!("INSERT INTO ai_audit_shadow_probe (audit_id) VALUES ($1)", [entry.id])
        end)
      end

      assert Repo.get!(AuditEntry, entry.id).user_id == user.id
    end

    test "the user FK can nilify its link while preserving actor attribution", %{
      user: user,
      entry: entry
    } do
      user
      |> Workspaces.get_default_workspace()
      |> Repo.delete!()

      Repo.delete!(user)

      refute Repo.get(User, user.id)

      reloaded = Repo.get(AuditEntry, entry.id)
      assert is_nil(reloaded.user_id)
      assert reloaded.actor_id == user.id
    end
  end
end
