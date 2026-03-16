defmodule Storyarn.Localization.TextExtractor do
  @moduledoc false

  alias Storyarn.Localization.LocalizableWords

  defdelegate extract_all(project_id), to: LocalizableWords
  defdelegate extract_flow_node(node), to: LocalizableWords
  defdelegate extract_flow(flow), to: LocalizableWords
  defdelegate extract_block(block), to: LocalizableWords
  defdelegate extract_sheet(sheet), to: LocalizableWords
  defdelegate extract_scene(scene), to: LocalizableWords

  defdelegate delete_flow_node_texts(node_id), to: LocalizableWords
  defdelegate delete_flow_texts(flow_id), to: LocalizableWords
  defdelegate delete_block_texts(block_id), to: LocalizableWords
  defdelegate delete_sheet_texts(sheet_id), to: LocalizableWords
  defdelegate delete_scene_texts(scene_id), to: LocalizableWords
end
