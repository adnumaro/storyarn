defmodule Storyarn.Accounts.Registration.Rules.DefaultWorkspace do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  def name_for(user) do
    display_name = user.display_name || extract_name_from_email(user.email)
    dgettext("identity", "%{name}'s workspace", name: display_name)
  end

  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.capitalize()
  end
end
