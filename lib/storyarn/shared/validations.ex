defmodule Storyarn.Shared.Validations do
  @moduledoc """
  Shared validation helpers for Ecto changesets.

  Centralizes duplicated validation patterns (shortcut format, email format)
  used across multiple schema modules.
  """

  import Ecto.Changeset

  @shortcut_format ~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/
  @email_format ~r/^[^@,;\s]+@[^@,;\s]+$/

  @doc """
  Returns the shortcut format regex.
  Lowercase alphanumeric with dots and hyphens, no leading/trailing special chars.
  """
  def shortcut_format, do: @shortcut_format

  @doc """
  Returns the email format regex.
  """
  def email_format, do: @email_format

  @doc """
  Validates shortcut format and length.

  Applies format regex and length constraints (1..50).
  Does NOT add `unique_constraint` — each schema must add its own
  since constraint names differ per table.
  """
  @spec validate_shortcut(Ecto.Changeset.t(), keyword()) :: Ecto.Changeset.t()
  def validate_shortcut(changeset, opts \\ []) do
    message =
      Keyword.get(
        opts,
        :message,
        "must be lowercase, alphanumeric, with dots or hyphens"
      )

    changeset
    |> validate_length(:shortcut, min: 1, max: 50)
    |> validate_format(:shortcut, @shortcut_format, message: message)
  end

  @doc """
  Validates email format.

  Applies the shared email regex. Does NOT add `unique_constraint`.
  """
  @spec validate_email_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_email_format(changeset) do
    validate_format(changeset, :email, @email_format,
      message: "must have the @ sign and no spaces"
    )
  end
end
