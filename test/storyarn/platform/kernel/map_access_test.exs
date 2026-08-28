defmodule Storyarn.Platform.Kernel.MapAccessTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Kernel.MapAccess

  test "normalizes only top-level atom keys" do
    assert MapAccess.stringify_keys(%{name: "Ada", nested: %{id: 1}}) == %{
             "name" => "Ada",
             "nested" => %{id: 1}
           }
  end

  test "preserves string keys and every value shape" do
    input =
      Map.put(
        %{
          string: "hello",
          number: 42,
          float: 3.14,
          boolean: true,
          missing: nil,
          list: [1, 2],
          nested: %{key: "value"}
        },
        "existing",
        "string key"
      )

    assert MapAccess.stringify_keys(input) == %{
             "string" => "hello",
             "number" => 42,
             "float" => 3.14,
             "boolean" => true,
             "missing" => nil,
             "list" => [1, 2],
             "nested" => %{key: "value"},
             "existing" => "string key"
           }

    assert MapAccess.stringify_keys(%{}) == %{}
  end

  test "reads atom and string representations without atomizing input" do
    assert MapAccess.get_flexible(%{name: "atom"}, :name) == "atom"
    assert MapAccess.get_flexible(%{"name" => "string"}, :name) == "string"
    assert MapAccess.get_flexible(%{"name" => "fallback", name: nil}, :name) == nil
  end
end
