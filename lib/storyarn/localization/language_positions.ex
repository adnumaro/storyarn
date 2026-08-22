defmodule Storyarn.Localization.LanguagePositions do
  @moduledoc false

  alias Storyarn.Repo

  @spec set_positions(integer(), [{integer(), non_neg_integer()}]) :: :ok
  def set_positions(_project_id, []), do: :ok

  def set_positions(project_id, id_position_pairs) when is_integer(project_id) and is_list(id_position_pairs) do
    {ids, positions} = Enum.unzip(id_position_pairs)

    Repo.query!(
      """
      UPDATE project_languages AS language
      SET position = data.position
      FROM unnest($1::bigint[], $2::int[]) AS data(id, position)
      WHERE language.id = data.id
        AND language.project_id = $3
      """,
      [ids, positions, project_id]
    )

    :ok
  end
end
