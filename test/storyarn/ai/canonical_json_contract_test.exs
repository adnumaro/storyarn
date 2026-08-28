defmodule Storyarn.AI.CanonicalJSONContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Operations.Rules.CanonicalJSON, as: OperationsCanonicalJSON
  alias Storyarn.AI.Routing.Rules.CanonicalJSON, as: RoutingCanonicalJSON

  test "routing and operations preserve the same wire representation" do
    values = [
      nil,
      true,
      42,
      3.5,
      "storyarn",
      [1, %{"nested" => false}],
      Map.new([{"z", 1}, {"a", [%{"b" => 2, "a" => 1}]}])
    ]

    for value <- values do
      assert {:ok, routing_bytes} = RoutingCanonicalJSON.encode(value)
      assert {:ok, operations_bytes} = OperationsCanonicalJSON.encode(value)
      assert operations_bytes == routing_bytes
    end
  end

  test "routing and operations reject the same unsupported values" do
    invalid_values = [%URI{}, %{:same => 1, "same" => 2}, [1 | 2], <<255>>]

    for value <- invalid_values do
      assert {:error, :invalid_structured_input} = RoutingCanonicalJSON.encode(value)
      assert {:error, :invalid_structured_input} = OperationsCanonicalJSON.encode(value)
    end
  end
end
