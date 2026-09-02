defmodule Storyarn.Projects.Imports.ImportFormatId do
  @moduledoc """
  Technical shape of the opaque format identifier stored by import records.

  This contract deliberately does not enumerate supported formats. The closed
  `Storyarn.Projects.Imports.FormatRegistry` is the sole authority for deciding
  whether the running release can parse or execute a format. Persistence only
  guarantees that the durable identifier is safe, bounded, and portable.
  """

  import Ecto.Changeset, only: [validate_format: 3, validate_length: 3]

  @max_length 30
  @pattern ~r/\A[a-z][a-z0-9_]*\z/

  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field \\ :format) do
    changeset
    |> validate_length(field, max: @max_length)
    |> validate_format(field, @pattern)
  end

  @spec valid?(term()) :: boolean()
  def valid?(format) when is_binary(format) do
    String.length(format) <= @max_length and Regex.match?(@pattern, format)
  end

  def valid?(_format), do: false
end
