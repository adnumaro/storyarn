defmodule Storyarn.Localization.Glossary do
  @moduledoc false

  alias Storyarn.Localization.Glossary.Commands.Entries, as: EntryCommands
  alias Storyarn.Localization.Glossary.Execution.Sync
  alias Storyarn.Localization.Glossary.Queries.Entries, as: EntryQueries

  defdelegate list_entries(project_id, opts \\ []), to: EntryQueries, as: :list
  defdelegate get_entry(project_id, id), to: EntryQueries, as: :get
  defdelegate get_entry!(project_id, id), to: EntryQueries, as: :get!
  defdelegate get_entries_for_pair(project_id, source_locale, target_locale), to: EntryQueries, as: :for_pair
  defdelegate list_entries_for_export(project_id), to: EntryQueries, as: :for_export

  defdelegate create_entry(project, attrs), to: EntryCommands, as: :create
  defdelegate update_entry(entry, attrs), to: EntryCommands, as: :update
  defdelegate delete_entry(entry), to: EntryCommands, as: :delete
  defdelegate bulk_import_entries(attrs_list), to: EntryCommands, as: :bulk_import

  defdelegate sync(project_id, source_locale, target_locale, opts \\ []), to: Sync
  defdelegate synced?(project_id, source_locale, target_locale), to: Sync
  defdelegate pair_key(source_locale, target_locale), to: Sync
end
