defmodule Storyarn.Imports.ImportPlan do
  @moduledoc """
  Parser-independent representation of a pending project import.

  `data` uses Storyarn's native import document so the existing transactional
  materializer remains the only database-writing implementation.
  """

  alias Storyarn.Imports.ImportIssue

  @enforce_keys [:format, :parser_version, :data]
  defstruct [:format, :parser_version, :data, :source_kind, issues: [], metadata: %{}]

  @type t :: %__MODULE__{
          format: atom(),
          parser_version: String.t(),
          data: map(),
          source_kind: atom() | nil,
          issues: [ImportIssue.t()],
          metadata: map()
        }

  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{issues: issues}) do
    Enum.any?(issues, &(&1.severity == :error))
  end

  @spec warning_codes(t()) :: [atom()]
  def warning_codes(%__MODULE__{issues: issues}) do
    issues
    |> Enum.filter(&(&1.severity == :warning))
    |> Enum.map(& &1.code)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
