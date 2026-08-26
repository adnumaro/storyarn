defmodule Storyarn.Sheets.AI.Contracts.ContextContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.Sheets.AI.ContextContract

  test "owns its scope, field groups, subject kind and source types" do
    assert {:ok, _policy} = Policy.new(policy(%{sheet_blocks: ["value"]}), ContextContract)

    assert {:error, :invalid_context_policy} =
             Policy.new(%{policy() | scope: :undeclared_sheet_scope}, ContextContract)

    assert {:error, :invalid_context_policy} =
             Policy.new(policy(%{speaker_blocks: ["Summary"]}), ContextContract)

    assert {:ok, ref} = ContextContract.sheet(1, 2, 3, block_ids: [4, 5])
    assert ContextContract.block_ids(ref) == [4, 5]
    assert {:ok, persisted} = SubjectRef.persisted_map(ref)
    assert {:ok, ^ref} = ContextContract.from_persisted_subject(persisted)

    assert {:error, :invalid_context_subject} =
             SubjectRef.new(ContextContract, :undeclared_sheet_kind, 1, 2, 3, %{block_ids: []})

    refute ContextContract.source_type?("undeclared_sheet_source", :included)
    refute ContextContract.source_type?("undeclared_sheet_source", :excluded)
  end

  defp policy(fields \\ %{}) do
    %{
      scope: :sheet,
      max_depth: 0,
      max_fan_out: 10,
      max_entities: 20,
      max_bytes: 16_384,
      tokenizer: nil,
      fields: fields
    }
  end
end
