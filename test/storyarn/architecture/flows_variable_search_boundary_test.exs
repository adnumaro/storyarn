defmodule Storyarn.Architecture.FlowsVariableSearchBoundaryTest do
  use ExUnit.Case, async: true

  @editor_info "lib/storyarn_web/live/flow_live/handlers/editor_info_handlers.ex"
  @picker_search "lib/storyarn_web/live/flow_live/picker_search.ex"

  test "Flow Web delegates variable search vocabulary and projection to the facade" do
    editor_info = File.read!(@editor_info)
    picker_search = File.read!(@picker_search)

    assert editor_info =~ "Flows.search_variable_suggestions"
    assert picker_search =~ "Flows.search_variable_options"

    for {path, source} <- [{@editor_info, editor_info}, {@picker_search, picker_search}],
        token <- ["sheet_shortcut", "variable_name"] do
      refute source =~ token,
             "#{path} must not own Flow variable vocabulary or construct variable references"
    end
  end
end
