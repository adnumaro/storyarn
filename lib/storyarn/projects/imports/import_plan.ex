defmodule Storyarn.Projects.Imports.ImportPlan do
  @moduledoc """
  Parser-independent representation of a pending project import.

  `data` uses Storyarn's native import document so the existing transactional
  materializer remains the only database-writing implementation.
  """

  alias Storyarn.Projects.Imports.ImportIssue

  @enforce_keys [:format, :parser_version, :data]
  defstruct [
    :format,
    :parser_version,
    :data,
    :source_kind,
    :attempt_binding,
    # Ephemeral parser metadata used only while creating the durable attempt.
    # It is intentionally absent from PlanStorage so parser-v5 plans remain
    # compatible with workers during a rolling deploy.
    replace_eligible: nil,
    issues: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          format: atom(),
          parser_version: String.t(),
          data: map(),
          source_kind: atom() | nil,
          attempt_binding: String.t() | nil,
          replace_eligible: boolean() | nil,
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
