defmodule Storyarn.Scenes.Exploration do
  @moduledoc """
  Public capability boundary for Scene exploration.

  It owns persisted play sessions, consumer-local Flow and Sheet projections,
  and the in-memory execution engine. Stable legacy module identities remain as
  implementation contracts while `Storyarn.Scenes` transitions to this facade.
  """

  alias Storyarn.Scenes.Exploration.Commands.Sessions, as: SessionCommands
  alias Storyarn.Scenes.Exploration.Events
  alias Storyarn.Scenes.Exploration.Queries.Sessions, as: SessionQueries
  alias Storyarn.Scenes.FlowCatalog
  alias Storyarn.Scenes.FlowRuntime.ConditionEval
  alias Storyarn.Scenes.FlowRuntime.Engine
  alias Storyarn.Scenes.FlowRuntime.EngineHelpers
  alias Storyarn.Scenes.FlowRuntime.FormulaRuntime
  alias Storyarn.Scenes.FlowRuntime.InstructionExec
  alias Storyarn.Scenes.FlowRuntime.PlayerEngine
  alias Storyarn.Scenes.FlowRuntime.Slide
  alias Storyarn.Scenes.FlowRuntime.Variables
  alias Storyarn.Scenes.SheetCatalog

  defdelegate get_session(user_id, project_id), to: SessionQueries
  defdelegate save_session(user_id, project_id, attrs), to: SessionCommands
  defdelegate delete_session(user_id, project_id), to: SessionCommands
  defdelegate cleanup_old_sessions(days \\ 30), to: SessionCommands

  defdelegate list_flows(project_id), to: FlowCatalog
  defdelegate search_flows(project_id, query, opts \\ []), to: FlowCatalog
  defdelegate get_flow(project_id, flow_id), to: FlowCatalog
  defdelegate get_runtime_flow(project_id, flow_id), to: FlowCatalog, as: :get_runtime_graph
  defdelegate runtime_nodes(project_id, flow_id), to: FlowCatalog
  defdelegate runtime_connections(project_id, flow_id), to: FlowCatalog

  defdelegate list_sheets_tree(project_id), to: SheetCatalog
  defdelegate list_all_sheets(project_id), to: SheetCatalog
  defdelegate search_sheets(project_id, query, opts \\ []), to: SheetCatalog
  defdelegate get_sheet(project_id, sheet_id), to: SheetCatalog

  defdelegate build_runtime_variables(project_id), to: Variables, as: :build_variables
  defdelegate runtime_init(variables, entry_id), to: Engine, as: :init

  defdelegate runtime_step_until_interactive(state, nodes, connections, opts \\ []),
    to: PlayerEngine,
    as: :step_until_interactive

  defdelegate runtime_choose_response(state, response_id, connections),
    to: Engine,
    as: :choose_response

  defdelegate runtime_step_back(state), to: Engine, as: :step_back

  defdelegate runtime_push_flow_context(state, node_id, nodes, connections, flow_name),
    to: Engine,
    as: :push_flow_context

  defdelegate runtime_pop_flow_context(state), to: Engine, as: :pop_flow_context

  defdelegate runtime_find_return_connection(connections, return_node_id, returned_exit_node_id),
    to: EngineHelpers,
    as: :find_return_connection

  defdelegate evaluate_runtime_condition(condition, variables), to: ConditionEval, as: :evaluate
  defdelegate execute_runtime_instructions(assignments, variables), to: InstructionExec, as: :execute
  defdelegate recompute_runtime_formulas(variables), to: FormulaRuntime, as: :recompute_formulas
  defdelegate build_runtime_slide(node, state, speakers_map, project_id), to: Slide, as: :build

  defdelegate format_runtime_value(value),
    to: Storyarn.Scenes.FlowRuntime.Helpers,
    as: :format_value

  def runtime_entry_node(nodes) when is_map(nodes) do
    Enum.find_value(nodes, fn {id, node} -> if node.type == "entry", do: id end)
  end

  defdelegate exploration_started(scope, scene, has_saved_session), to: Events
end
