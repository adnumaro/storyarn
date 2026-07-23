defmodule Storyarn.AI.AuditTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.AI.Audit
  alias Storyarn.AI.AuditEntry
  alias Storyarn.Repo

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

    test "the trigger permits the FK nilify transition, preserving actor attribution", %{
      user: user,
      entry: entry
    } do
      # This UPDATE is byte-identical to what ON DELETE SET NULL fires when
      # the user row is deleted — the only mutation the trigger lets through.
      Repo.query!("UPDATE ai_integration_audits SET user_id = NULL WHERE id = $1", [entry.id])

      reloaded = Repo.get(AuditEntry, entry.id)
      assert is_nil(reloaded.user_id)
      assert reloaded.actor_id == user.id
    end
  end
end
