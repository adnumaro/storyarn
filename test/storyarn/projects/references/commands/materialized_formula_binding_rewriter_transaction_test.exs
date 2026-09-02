defmodule Storyarn.Projects.References.MaterializedFormulaBindingRewriterTransactionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Projects.References.MaterializedFormulaBindingRewriter
  alias Storyarn.Repo

  test "rejects a rewrite outside a caller-owned transaction" do
    assert {:error, :materialized_formula_binding_rewrite_requires_transaction} =
             Sandbox.unboxed_run(Repo, fn ->
               refute Repo.in_transaction?()
               MaterializedFormulaBindingRewriter.rewrite(1, %{}, %{})
             end)
  end
end
