Code.require_file(Path.expand("../migration_helpers/runtime_localization_repair.exs", __DIR__))

defmodule Storyarn.Repo.Migrations.RepairRuntimeLocalizationBackfill do
  use Ecto.Migration

  alias Storyarn.Repo.Migrations.RuntimeLocalizationRepair

  def up do
    execute(RuntimeLocalizationRepair.lock_sql())
    Enum.each(RuntimeLocalizationRepair.runtime_id_sql(), &execute/1)
    Enum.each(RuntimeLocalizationRepair.locale_sql(), &execute/1)
  end

  # The repair only replaces ambiguous or invalid legacy identifiers and merges
  # case-equivalent locales. Neither transformation has a reliable inverse.
  def down, do: :ok
end
