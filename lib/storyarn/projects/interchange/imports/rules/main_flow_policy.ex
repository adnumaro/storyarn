defmodule Storyarn.Projects.Imports.MainFlowPolicy do
  @moduledoc """
  Resolves the single-main-flow invariant for project imports.

  Source adapters may nominate a flow by setting `is_main`, but the target
  project decides whether that nomination can be applied. The decision is made
  again while the project row is locked, so a preview is informative rather
  than authoritative.
  """

  @type existing_main :: nil | %{required(:shortcut) => String.t() | nil}
  @type state :: %{
          required(:main_claimed?) => boolean(),
          required(:existing_main_shortcut) => String.t() | nil
        }

  @doc "Returns the materialization state for the target project's active main flow."
  @spec initial_state(existing_main()) :: state()
  def initial_state(nil), do: %{main_claimed?: false, existing_main_shortcut: nil}

  def initial_state(%{shortcut: shortcut}) do
    %{main_claimed?: true, existing_main_shortcut: shortcut}
  end

  @doc """
  Decides whether one resolved imported flow must be persisted as main.

  Overwriting the active main flow transfers its role to the replacement.
  Otherwise an adapter nomination is accepted only when the project has no
  active main flow and no earlier imported flow has claimed the role.
  """
  @spec resolve(map(), String.t() | nil, atom(), state()) :: {boolean(), state()}
  def resolve(flow_data, resolved_shortcut, strategy, state) do
    cond do
      overwrites_existing_main?(resolved_shortcut, strategy, state) ->
        {true, %{state | main_claimed?: true, existing_main_shortcut: nil}}

      state.main_claimed? ->
        {false, state}

      flow_data["is_main"] == true ->
        {true, %{state | main_claimed?: true}}

      true ->
        {false, state}
    end
  end

  @doc """
  Builds every user-selectable preview outcome from current target facts.

  Returning the complete matrix lets the UI react immediately when the user
  changes mode or conflict strategy. Materialization still recalculates the
  decision under the project lock.
  """
  @spec preview([map()], existing_main(), [String.t()]) :: map()
  def preview(flows, existing_main, conflicting_shortcuts) do
    candidates = Enum.filter(flows, &(&1["is_main"] == true))
    conflict_set = MapSet.new(conflicting_shortcuts)
    target_has_main? = not is_nil(existing_main)
    candidate_exists? = candidates != []

    candidate_survives_skip? =
      Enum.any?(candidates, fn candidate ->
        not MapSet.member?(conflict_set, candidate["shortcut"])
      end)

    overwrites_target_main? =
      target_has_main? and
        is_binary(existing_main.shortcut) and
        Enum.any?(flows, &(&1["shortcut"] == existing_main.shortcut))

    %{
      additive: %{
        skip: additive_outcome(target_has_main?, candidate_survives_skip?, false),
        overwrite: additive_outcome(target_has_main?, candidate_exists?, overwrites_target_main?),
        rename: additive_outcome(target_has_main?, candidate_exists?, false)
      },
      replace_project: if(candidate_exists?, do: "import_candidate", else: "none")
    }
  end

  defp overwrites_existing_main?(resolved_shortcut, :overwrite, %{existing_main_shortcut: existing_main_shortcut}) do
    is_binary(existing_main_shortcut) and resolved_shortcut == existing_main_shortcut
  end

  defp overwrites_existing_main?(_resolved_shortcut, _strategy, _state), do: false

  defp additive_outcome(true, _candidate_available?, true), do: "replace_existing"
  defp additive_outcome(true, _candidate_available?, false), do: "preserve_existing"
  defp additive_outcome(false, true, _overwrites_target_main?), do: "import_candidate"
  defp additive_outcome(false, false, _overwrites_target_main?), do: "none"
end
