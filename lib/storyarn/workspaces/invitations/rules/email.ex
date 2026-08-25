defmodule Storyarn.Workspaces.Invitations.Rules.Email do
  @moduledoc false

  import Ecto.Changeset, only: [validate_format: 4]

  @email_format ~r/^[^@,;\s]+@[^@,;\s]+$/

  def normalize(email), do: email |> String.trim() |> String.downcase()

  def validate_changeset(changeset) do
    validate_format(changeset, :email, @email_format, message: "must have the @ sign and no spaces")
  end
end
