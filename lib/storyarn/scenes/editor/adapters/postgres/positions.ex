defmodule Storyarn.Scenes.Editor.Adapters.Postgres.Positions do
  @moduledoc """
  PostgreSQL implementation of the editor's bulk position updates.

  These statements deliberately live behind the editor capability: the
  commands decide when a reorder is valid, while this adapter preserves the
  existing constant-number-of-writes implementation.
  """

  alias Storyarn.Repo

  def set_scene_positions([], _project_id, _parent_id), do: :ok

  # The table and columns are fixed Scene-owned identifiers; only values are
  # parameters. One update preserves the existing O(1) write behavior.
  # sobelow_skip ["SQL.Query"]
  def set_scene_positions(id_position_pairs, project_id, nil) do
    {ids, positions} = Enum.unzip(id_position_pairs)

    Repo.query!(
      """
      UPDATE scenes
      SET position = data.pos
      FROM unnest($1::bigint[], $2::int[]) AS data(id, pos)
      WHERE scenes.id = data.id
        AND scenes.project_id = $3
        AND scenes.parent_id IS NULL
        AND scenes.deleted_at IS NULL
      """,
      [ids, positions, project_id]
    )

    :ok
  end

  # sobelow_skip ["SQL.Query"]
  def set_scene_positions(id_position_pairs, project_id, parent_id) do
    {ids, positions} = Enum.unzip(id_position_pairs)

    Repo.query!(
      """
      UPDATE scenes
      SET position = data.pos
      FROM unnest($1::bigint[], $2::int[]) AS data(id, pos)
      WHERE scenes.id = data.id
        AND scenes.project_id = $3
        AND scenes.parent_id = $4
        AND scenes.deleted_at IS NULL
      """,
      [ids, positions, project_id, parent_id]
    )

    :ok
  end

  def set_layer_positions([], _scene_id), do: :ok

  # The table and columns are fixed Scene-owned identifiers; only values are
  # parameters.
  # sobelow_skip ["SQL.Query"]
  def set_layer_positions(id_position_pairs, scene_id)
      when is_list(id_position_pairs) and is_integer(scene_id) and scene_id > 0 do
    {ids, positions} = Enum.unzip(id_position_pairs)

    Repo.query!(
      """
      UPDATE scene_layers
      SET position = data.pos
      FROM unnest($1::bigint[], $2::int[]) AS data(id, pos)
      WHERE scene_layers.id = data.id
        AND scene_layers.scene_id = $3
      """,
      [ids, positions, scene_id]
    )
  end
end
