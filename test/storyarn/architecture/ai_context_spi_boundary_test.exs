defmodule Storyarn.Architecture.AIContextSPIBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @spis %{
    "lib/storyarn/ai/context/contracts/contract.ex" => "Storyarn.AI.Context.Contract",
    "lib/storyarn/ai/context/contracts/policy.ex" => "Storyarn.AI.Context.Policy",
    "lib/storyarn/ai/context/contracts/subject_ref.ex" => "Storyarn.AI.Context.SubjectRef"
  }
  @consumer_implementations ~w(
    lib/storyarn/flows/ai/contracts/context_contract.ex
    lib/storyarn/sheets/ai/contracts/context_contract.ex
  )

  test "consumer-owned Context SPIs keep their stable module identities at exact contract paths" do
    Enum.each(@spis, fn {path, module} ->
      assert File.exists?(path)
      assert File.read!(path) =~ ~r/^defmodule #{Regex.escape(module)} do/m
    end)

    for legacy <- ~w(
          lib/storyarn/ai/context/contract.ex
          lib/storyarn/ai/context/policy.ex
          lib/storyarn/ai/context/subject_ref.ex
        ) do
      refute File.exists?(legacy), "#{legacy} must not return as a second public SPI location"
    end
  end

  test "the ratchet exposes only the three exact Context SPI files" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    ai_contract_targets =
      policy.additional_durable_contract_targets
      |> Enum.map(& &1.target)
      |> Enum.filter(&String.starts_with?(&1, "lib/storyarn/ai/"))
      |> Enum.sort()

    assert ai_contract_targets == @spis |> Map.keys() |> Enum.sort()

    ai_internal_contracts =
      Enum.filter(policy.durable_contracts, &String.starts_with?(&1.target, "lib/storyarn/ai/"))

    assert length(ai_internal_contracts) == 6
    assert ai_internal_contracts |> Enum.map(& &1.source) |> Enum.uniq() |> Enum.sort() == @consumer_implementations
    assert Enum.all?(ai_internal_contracts, &Map.has_key?(@spis, &1.target))
  end
end
