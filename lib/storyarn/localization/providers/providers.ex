defmodule Storyarn.Localization.Providers do
  @moduledoc false

  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Providers.Commands.Configuration
  alias Storyarn.Localization.Providers.Commands.GlossaryState
  alias Storyarn.Localization.Providers.DeepL
  alias Storyarn.Localization.Providers.Queries.Configuration, as: ConfigurationQueries

  defdelegate get_config(project_id, provider \\ "deepl"), to: ConfigurationQueries, as: :get
  defdelegate fetch_active_config(project_id, provider \\ "deepl"), to: ConfigurationQueries, as: :fetch_active
  defdelegate active?(project_id, provider \\ "deepl"), to: ConfigurationQueries
  defdelegate upsert_config(actor_scope, project, attrs), to: Configuration, as: :upsert

  def change_config(config \\ nil) do
    config = config || %ProviderConfig{api_endpoint: ProviderConfig.default_api_endpoint()}
    ProviderConfig.changeset(config, %{})
  end

  defdelegate get_usage(config), to: DeepL

  defdelegate persist_glossary_pair(config, pair, glossary_id, hash),
    to: GlossaryState,
    as: :persist_pair

  defdelegate persist_glossary_pair_if_current(config, pair, expected_id, glossary_id, hash),
    to: GlossaryState,
    as: :persist_pair_if_current

  defdelegate persist_pending_glossary_deletion(config, glossary_id, pending?),
    to: GlossaryState,
    as: :persist_pending_deletion

  @spec default_adapter() :: module()
  def default_adapter, do: DeepL
end
