defmodule StoryarnWeb.IdeationLive.Helpers.Replies do
  @moduledoc false

  def error(%Ecto.Changeset{} = changeset) do
    fields = Ecto.Changeset.traverse_errors(changeset, fn _ -> "invalid" end)
    %{status: "error", code: "validation", fields: Map.keys(fields)}
  end

  def error(reason) when is_atom(reason), do: %{status: "error", code: Atom.to_string(reason)}
  def error(_), do: %{status: "error", code: "unavailable"}

  def result({:ok, value}), do: %{status: "ok", value: value}
  def result({:error, reason}), do: error(reason)

  def equivalent?(attempted, current) do
    Enum.all?([:title, :body, :state], fn field -> Map.get(attempted, field) == Map.get(current, field) end)
  end
end
