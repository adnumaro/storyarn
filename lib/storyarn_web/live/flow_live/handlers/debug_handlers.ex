defmodule StoryarnWeb.FlowLive.Handlers.DebugHandlers do
  @moduledoc """
  Facade module — delegates to DebugExecutionHandlers and DebugSessionHandlers.
  """

  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers
  alias StoryarnWeb.FlowLive.Handlers.DebugSessionHandlers

  # Session lifecycle
  defdelegate handle_debug_start(socket), to: DebugSessionHandlers
  defdelegate handle_debug_change_start_node(params, socket), to: DebugSessionHandlers
  defdelegate handle_debug_reset(socket), to: DebugSessionHandlers
  defdelegate handle_debug_stop(socket), to: DebugSessionHandlers
  defdelegate handle_debug_tab_change(params, socket), to: DebugSessionHandlers
  defdelegate handle_debug_edit_variable(params, socket), to: DebugSessionHandlers
  defdelegate handle_debug_cancel_edit(socket), to: DebugSessionHandlers
  defdelegate handle_debug_set_variable(params, socket), to: DebugSessionHandlers
  defdelegate handle_debug_var_filter(params, socket), to: DebugSessionHandlers
  defdelegate handle_debug_var_toggle_changed(socket), to: DebugSessionHandlers
  defdelegate handle_debug_toggle_breakpoint(params, socket), to: DebugSessionHandlers

  # Execution
  defdelegate handle_debug_step(socket), to: DebugExecutionHandlers
  defdelegate handle_debug_step_back(socket), to: DebugExecutionHandlers
  defdelegate handle_debug_choose_response(params, socket), to: DebugExecutionHandlers
  defdelegate handle_debug_play(socket), to: DebugExecutionHandlers
  defdelegate handle_debug_pause(socket), to: DebugExecutionHandlers
  defdelegate handle_debug_set_speed(params, socket), to: DebugExecutionHandlers
  defdelegate handle_debug_auto_step(socket), to: DebugExecutionHandlers
end
