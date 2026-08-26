defmodule Storyarn.Flows.Runtime do
  @moduledoc """
  Public capability boundary for Flow evaluation, player and debugger runtime.

  It keeps runtime orchestration behind one entry point while the existing
  evaluator and session modules retain their stable identities.
  """

  alias Storyarn.Flows.DebugSession
  alias Storyarn.Flows.DebugSessionStore
  alias Storyarn.Flows.DialoguePreview
  alias Storyarn.Flows.Evaluator.ConditionEval
  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Flows.Evaluator.EngineHelpers
  alias Storyarn.Flows.Evaluator.Helpers
  alias Storyarn.Flows.Evaluator.InstructionExec
  alias Storyarn.Flows.NavigationHistoryStore
  alias Storyarn.Flows.PlayerCatalog
  alias Storyarn.Flows.PlayerEngine
  alias Storyarn.Flows.PlayerOutcome
  alias Storyarn.Flows.PlayerSession
  alias Storyarn.Flows.PlayerText
  alias Storyarn.Flows.RuntimeGraph
  alias Storyarn.Flows.RuntimeVariables
  alias Storyarn.Flows.SceneResolver
  alias Storyarn.Flows.SequenceComposition
  alias Storyarn.Flows.Supervisor, as: RuntimeSupervisor

  @doc false
  def child_spec(opts) do
    %{
      id: Storyarn.Flows,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  defdelegate start_link(opts), to: RuntimeSupervisor

  defdelegate resolve_scene_id(flow, opts \\ []), to: SceneResolver
  defdelegate load_player_speakers(project_id), to: PlayerCatalog, as: :load_speakers

  defdelegate evaluator_init(variables, start_node_id), to: Engine, as: :init

  defdelegate player_step_until_interactive(state, nodes, connections, opts \\ []),
    to: PlayerEngine,
    as: :step_until_interactive

  defdelegate start_player_session(flow, variables), to: PlayerSession, as: :start

  defdelegate restore_player_session(flow, state, nodes, connections, scene_id),
    to: PlayerSession,
    as: :restore

  defdelegate record_player_started(scope_or_user, flow),
    to: PlayerSession,
    as: :record_started

  defdelegate continue_player_session(session), to: PlayerSession, as: :continue

  defdelegate choose_player_response(session, response_id),
    to: PlayerSession,
    as: :choose_response

  defdelegate player_response_id_by_number(responses, mode, number),
    to: PlayerSession,
    as: :response_id_by_number

  defdelegate go_back_player_session(session), to: PlayerSession, as: :go_back
  defdelegate restart_player_session(session), to: PlayerSession, as: :restart
  defdelegate player_session_can_go_back?(session), to: PlayerSession, as: :can_go_back?
  defdelegate compose_player_sequences(state, nodes), to: SequenceComposition, as: :compose

  defdelegate interpolate_player_rich_text(text, variables, renderer),
    to: PlayerText,
    as: :interpolate_rich_text

  defdelegate map_player_rich_text_references(text, renderer),
    to: PlayerText,
    as: :map_rich_text_references

  defdelegate interpolate_player_response_text(text, variables),
    to: PlayerText,
    as: :interpolate_response_text

  defdelegate format_player_value(value), to: PlayerText, as: :format_value
  defdelegate build_player_outcome(node, state), to: PlayerOutcome, as: :build

  defdelegate evaluator_step(state, nodes, connections), to: Engine, as: :step
  defdelegate evaluator_step_back(state), to: Engine, as: :step_back

  defdelegate evaluator_choose_response(state, response_id, connections),
    to: Engine,
    as: :choose_response

  defdelegate evaluator_push_flow_context(state, node_id, nodes, connections, flow_name),
    to: Engine,
    as: :push_flow_context

  defdelegate evaluator_pop_flow_context(state), to: Engine, as: :pop_flow_context

  defdelegate evaluator_find_return_connection(connections, return_node_id, returned_exit_node_id),
    to: EngineHelpers,
    as: :find_return_connection

  defdelegate evaluator_reset(state), to: Engine, as: :reset
  defdelegate evaluator_toggle_breakpoint(state, node_id), to: Engine, as: :toggle_breakpoint
  defdelegate evaluator_at_breakpoint?(state), to: Engine, as: :at_breakpoint?
  defdelegate evaluator_add_breakpoint_hit(state, node_id), to: Engine, as: :add_breakpoint_hit
  defdelegate evaluator_set_variable(state, key, value), to: Engine, as: :set_variable
  defdelegate evaluator_extend_step_limit(state), to: Engine, as: :extend_step_limit

  defdelegate evaluator_add_console_entry(state, level, node_id, label, message),
    to: Engine,
    as: :add_console_entry

  def evaluator_strip_html(text, max_length \\ 40), do: Helpers.strip_html(text, max_length)
  defdelegate evaluator_format_value(value), to: Helpers, as: :format_value
  defdelegate evaluate_condition(condition, variables), to: ConditionEval, as: :evaluate
  defdelegate execute_instructions(assignments, variables), to: InstructionExec, as: :execute

  defdelegate build_runtime_variables(project_id), to: RuntimeVariables, as: :build
  defdelegate start_dialogue_preview(flow_id, node_id), to: DialoguePreview, as: :start

  defdelegate follow_dialogue_preview(flow_id, node_id, source_pin),
    to: DialoguePreview,
    as: :follow

  defdelegate load_runtime_graph(flow_id), to: RuntimeGraph, as: :load
  defdelegate runtime_entry_node_id(nodes), to: RuntimeGraph, as: :entry_node_id
  defdelegate debug_active_connection(path, connections), to: RuntimeGraph, as: :active_connection

  defdelegate start_debug_session(scope_or_user, flow), to: DebugSession, as: :start

  defdelegate debug_select_start_node(state, nodes, node_id),
    to: DebugSession,
    as: :select_start_node

  defdelegate debug_step(state, nodes, connections, flow_name), to: DebugSession, as: :step
  defdelegate debug_auto_step(state, nodes, connections, flow_name), to: DebugSession, as: :auto_step
  defdelegate debug_step_back(state), to: DebugSession, as: :step_back

  defdelegate debug_choose_response(state, response_id, connections),
    to: DebugSession,
    as: :choose_response

  defdelegate reset_debug_session(state, nodes, connections), to: DebugSession, as: :reset
  defdelegate stop_debug_session(), to: DebugSession, as: :stop
  defdelegate set_debug_variable(state, key, raw_value), to: DebugSession, as: :set_variable
  defdelegate extend_debug_step_limit(state), to: DebugSession, as: :extend_step_limit
  defdelegate toggle_debug_breakpoint(state, node_id), to: DebugSession, as: :toggle_breakpoint

  defdelegate debug_session_store(key, data), to: DebugSessionStore, as: :store
  defdelegate debug_session_take(key), to: DebugSessionStore, as: :take
  defdelegate nav_history_get(key), to: NavigationHistoryStore, as: :get
  defdelegate nav_history_put(key, data), to: NavigationHistoryStore, as: :put
  defdelegate nav_history_clear(key), to: NavigationHistoryStore, as: :clear
end
