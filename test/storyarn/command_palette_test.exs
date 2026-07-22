defmodule Storyarn.CommandPaletteTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.CommandPalette
  alias Storyarn.CommandPalette.Operation
  alias Storyarn.Repo

  test "commits a successful mutation and its replay result atomically" do
    scope = user_scope_fixture()
    operation_id = "create-once"

    assert {%{url: "/sheets/123"}, :broadcast} =
             CommandPalette.run(
               scope,
               "palette_create",
               operation_id,
               fn ->
                 send(self(), :executed)
                 {%{url: "/sheets/123"}, :broadcast}
               end,
               fn _reason -> %{error: "failed"} end
             )

    assert_receive :executed

    assert {%{url: "/sheets/123"}, nil} =
             CommandPalette.run(
               scope,
               "palette_create",
               operation_id,
               fn ->
                 send(self(), :executed_twice)
                 {%{url: "/sheets/999"}, :broadcast}
               end,
               fn _reason -> %{error: "failed"} end
             )

    refute_receive :executed_twice
  end

  test "preserves rollback reasons and allows a failed operation id to be retried" do
    scope = user_scope_fixture()
    operation_id = "retry-after-limit"

    assert {%{error: "limit_reached"}, nil} =
             CommandPalette.run(
               scope,
               "palette_create",
               operation_id,
               fn -> Repo.rollback({:limit_reached, %{limit: 1}}) end,
               fn
                 {:limit_reached, _details} -> %{error: "limit_reached"}
                 _reason -> %{error: "failed"}
               end
             )

    refute Repo.get_by(Operation,
             user_id: scope.user.id,
             event: "palette_create",
             operation_id: operation_id
           )

    assert {%{url: "/sheets/123"}, :broadcast} =
             CommandPalette.run(
               scope,
               "palette_create",
               operation_id,
               fn -> {%{url: "/sheets/123"}, :broadcast} end,
               fn _reason -> %{error: "failed"} end
             )
  end
end
