defmodule Storyarn.Ideation.Ideas.Rules.Selection do
  @moduledoc false
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1, valid_revision: 1]

  alias Storyarn.Ideation.Ideas.Rules.Input

  def normalize(:eligible), do: {:ok, %{"mode" => "eligible"}}

  def normalize(targets) when is_list(targets) and length(targets) in 1..200 do
    normalized = Enum.map(targets, &target/1)

    if Enum.any?(normalized, &is_nil/1) or length(Enum.uniq_by(normalized, & &1["idea_id"])) != length(targets),
      do: {:error, :invalid_selection},
      else: {:ok, %{"mode" => "selected", "targets" => Enum.sort_by(normalized, & &1["idea_id"])}}
  end

  def normalize(_), do: {:error, :invalid_selection}

  defp target(value) when is_map(value) do
    id = Input.get(value, :idea_id)
    revision = Input.get(value, :revision)
    if valid_id(id) and valid_revision(revision), do: %{"idea_id" => id, "revision" => revision}
  end

  defp target(_), do: nil
end
