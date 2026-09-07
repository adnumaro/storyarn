defmodule Storyarn.Repo.Migrations.AddAccountRecoveryIdentity do
  use Ecto.Migration

  def up do
    # Adding a volatile default with the column would rewrite the whole table.
    alter table(:users), do: add(:recovery_identity, :uuid)
    execute "ALTER TABLE users ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE users SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:users), do: modify(:recovery_identity, :uuid, null: false)
    create unique_index(:users, [:recovery_identity])
  end

  def down do
    drop unique_index(:users, [:recovery_identity])
    alter table(:users), do: remove(:recovery_identity)
  end
end
