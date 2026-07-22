defmodule Storyarn.AI.AllowanceAccount do
  @moduledoc "Execution-time projection of one workspace's managed AI allowance."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Workspaces.Workspace

  schema "ai_allowance_accounts" do
    field :status, :string, default: "active"
    field :available_units, :integer, default: 0
    field :reserved_units, :integer, default: 0
    field :committed_units, :integer, default: 0

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  def create_changeset(account, workspace_id) do
    account
    |> change(workspace_id: workspace_id)
    |> validate_required([:workspace_id, :status, :available_units, :reserved_units, :committed_units])
    |> validate_inclusion(:status, ~w(active paused))
    |> validate_number(:available_units, greater_than_or_equal_to: 0)
    |> validate_number(:reserved_units, greater_than_or_equal_to: 0)
    |> validate_number(:committed_units, greater_than_or_equal_to: 0)
    |> unique_constraint(:workspace_id)
    |> foreign_key_constraint(:workspace_id)
  end

  def balance_changeset(account, attrs) do
    account
    |> cast(attrs, [:status, :available_units, :reserved_units, :committed_units])
    |> validate_required([:status, :available_units, :reserved_units, :committed_units])
    |> validate_inclusion(:status, ~w(active paused))
    |> validate_number(:available_units, greater_than_or_equal_to: 0)
    |> validate_number(:reserved_units, greater_than_or_equal_to: 0)
    |> validate_number(:committed_units, greater_than_or_equal_to: 0)
  end
end
