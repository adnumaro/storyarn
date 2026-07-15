defmodule Storyarn.Imports.ImportIssue do
  @moduledoc """
  A safe, structured diagnostic produced while parsing an import.

  `source` is an opaque alias assigned by `SourceBundle` (for example,
  `source_2`), never the uploaded filename. Imported text is deliberately not
  part of this structure.
  """

  @enforce_keys [:severity, :code]
  defstruct [:severity, :code, :source, :line, :column, context: %{}]

  @type severity :: :warning | :error
  @type t :: %__MODULE__{
          severity: severity(),
          code: atom(),
          source: String.t() | nil,
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          context: map()
        }

  @spec new(severity(), atom(), keyword()) :: t()
  def new(severity, code, opts \\ []) when severity in [:warning, :error] and is_atom(code) do
    %__MODULE__{
      severity: severity,
      code: code,
      source: Keyword.get(opts, :source),
      line: Keyword.get(opts, :line),
      column: Keyword.get(opts, :column),
      context: Keyword.get(opts, :context, %{})
    }
  end
end
