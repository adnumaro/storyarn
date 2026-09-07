defmodule Storyarn.Flows.Localization do
  @moduledoc """
  Capability boundary for Flow-localizable content and Localization commands.

  Flows owns the source vocabulary and word-count semantics. The Localization
  context owns extraction and the shared inventory; this boundary exposes only
  the commands required by Flow workflows.
  """

  alias Storyarn.Flows.ContentContract
  alias Storyarn.Flows.WordCount
  alias Storyarn.Localization, as: LocalizationOwner

  defdelegate localizable_node_types(), to: ContentContract
  defdelegate node_word_count(type, data), to: WordCount, as: :for_node_data
  # Flow snapshot build already owns a Project row lock. Preserve its historical
  # SHARE -> Flow -> advisory order instead of upgrading Project after Flow.
  def lock_inventory!(project_id), do: LocalizationOwner.lock_inventory_after_project_lock!(project_id)
  defdelegate extract_flow_node(node), to: LocalizationOwner
  defdelegate extract_flow_nodes(flow_id), to: LocalizationOwner

  defdelegate flow_node_texts_current_ids(nodes, project_id),
    to: LocalizationOwner

  defdelegate delete_flow_node_texts(node_id), to: LocalizationOwner
  defdelegate delete_flow_node_texts_for_flows(flow_ids), to: LocalizationOwner

  def purge_texts_for_sources("flow_node", source_ids), do: LocalizationOwner.purge_flow_node_texts(source_ids)

  @doc "Lists the active project languages used by Flow presentation surfaces."
  def list_languages(project_id) do
    project_id
    |> LocalizationOwner.list_languages()
    |> Enum.map(&language_projection/1)
  end

  @doc "Returns the project's source language for Flow presentation surfaces."
  def get_source_language(project_id) do
    project_id
    |> LocalizationOwner.get_source_language()
    |> language_projection()
  end

  @doc "Returns Flow-owned projections of localized rows for one source."
  def get_texts_for_source(source_type, source_id) do
    source_type
    |> LocalizationOwner.get_texts_for_source(source_id)
    |> Enum.map(&text_projection/1)
  end

  @doc "Returns a Flow-owned projection of one localized source field."
  def get_text_by_source(source_type, source_id, source_field, locale_code) do
    source_type
    |> LocalizationOwner.get_text_by_source(source_id, source_field, locale_code)
    |> text_projection()
  end

  defp language_projection(nil), do: nil

  defp language_projection(language) do
    Map.take(language, [:id, :locale_code, :name, :is_source])
  end

  defp text_projection(nil), do: nil

  defp text_projection(text) do
    text
    |> Map.take([:locale_code, :source_field, :translated_text, :status, :vo_status, :vo_asset_id])
    |> Map.put(:stale, LocalizationOwner.text_stale?(text))
  end
end
