defmodule Storyarn.Exports.ExpressionTranspiler do
  @moduledoc """
  Behaviour for engine-specific expression transpilers.

  Converts Storyarn structured conditions and instruction assignments
  into target engine scripting syntax. Each engine implements this
  behaviour with its own variable reference format, operator syntax,
  and logic combinators.

  ## Engines

  | Engine | Module | Variable Format |
  |--------|--------|-----------------|
  | Ink    | `ExpressionTranspiler.Ink`    | `mc_jaime_health` |
  | Yarn   | `ExpressionTranspiler.Yarn`   | `$mc_jaime_health` |
  | Unity  | `ExpressionTranspiler.Unity`  | `Variable["mc.jaime.health"]` |
  | Godot  | `ExpressionTranspiler.Godot`  | `mc_jaime_health` |
  | Unreal | `ExpressionTranspiler.Unreal` | `mc.jaime.health` |
  | articy | `ExpressionTranspiler.Articy` | `mc.jaime.health` |

  ## Usage

      {:ok, expr, warnings} = ExpressionTranspiler.transpile_condition(condition, :ink)
      {:ok, expr, warnings} = ExpressionTranspiler.transpile_instruction(assignments, :yarn)
  """

  alias Storyarn.Exports.ExpressionTranspiler.Helpers

  @type warning :: %{type: atom(), message: String.t(), details: map()}

  @doc "Transpile a structured condition to target engine syntax."
  @callback transpile_condition(condition :: map(), context :: map()) ::
              {:ok, String.t(), [warning()]} | {:error, term()}

  @doc "Transpile structured instruction assignments to target engine syntax."
  @callback transpile_instruction(assignments :: [map()], context :: map()) ::
              {:ok, String.t(), [warning()]} | {:error, term()}

  # ---------------------------------------------------------------------------
  # Registry
  # ---------------------------------------------------------------------------

  @emitters %{
    ink: Storyarn.Exports.ExpressionTranspiler.Ink,
    yarn: Storyarn.Exports.ExpressionTranspiler.Yarn,
    unity: Storyarn.Exports.ExpressionTranspiler.Unity,
    godot: Storyarn.Exports.ExpressionTranspiler.Godot,
    unreal: Storyarn.Exports.ExpressionTranspiler.Unreal,
    articy: Storyarn.Exports.ExpressionTranspiler.Articy
  }

  @doc "Transpile a condition for the given engine. Handles all storage formats."
  @spec transpile_condition(term(), atom(), map()) ::
          {:ok, String.t(), [warning()]} | {:error, term()}
  def transpile_condition(raw_condition, engine, context \\ %{}) do
    with {:ok, module} <- fetch_emitter(engine),
         {:ok, condition} <- Helpers.decode_condition(raw_condition) do
      module.transpile_condition(condition, context)
    end
  end

  @doc "Transpile instruction assignments for the given engine."
  @spec transpile_instruction([map()], atom(), map()) ::
          {:ok, String.t(), [warning()]} | {:error, term()}
  def transpile_instruction(assignments, engine, context \\ %{}) do
    with {:ok, module} <- fetch_emitter(engine) do
      module.transpile_instruction(assignments || [], context)
    end
  end

  @doc "Returns the list of supported engine atoms."
  @spec engines() :: [atom()]
  def engines, do: Map.keys(@emitters)

  defp fetch_emitter(engine) do
    case Map.fetch(@emitters, engine) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_engine, engine}}
    end
  end
end
