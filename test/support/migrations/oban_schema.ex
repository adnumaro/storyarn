defmodule Storyarn.Test.Migrations.ObanSchema do
  @moduledoc false

  use Ecto.Migration

  def up, do: Oban.Migrations.up(prefix: prefix(), create_schema: false)
  def down, do: Oban.Migrations.down(prefix: prefix())
end
