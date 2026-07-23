defmodule Storyarn.AI.ConfigMapTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.ConfigMap

  test "normalizes keyword and atom-keyed configuration consistently" do
    assert ConfigMap.normalize(region: "global", nested: %{kept: true}) == %{
             "region" => "global",
             "nested" => %{kept: true}
           }

    assert ConfigMap.normalize(%{region: "global"}) == %{"region" => "global"}
    assert ConfigMap.normalize(:invalid) == %{}
  end
end
