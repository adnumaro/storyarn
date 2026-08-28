defmodule Storyarn.Flows.RuntimeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Runtime

  test "keeps the established Flow supervisor child identity" do
    assert Runtime.child_spec(:runtime) == %{
             id: Storyarn.Flows,
             start: {Runtime, :start_link, [:runtime]},
             type: :supervisor
           }
  end

  test "exposes both evaluator strip-html arities" do
    assert Runtime.evaluator_strip_html("<p>Dialogue</p>") == "Dialogue"
    assert Runtime.evaluator_strip_html("<p>Long dialogue</p>", 4) == "Long"
  end
end
