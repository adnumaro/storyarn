defmodule Storyarn.Workspaces.Memberships.Rules.OwnerProtection do
  @moduledoc false

  @spec allow_role_change(map()) :: :ok | {:error, :cannot_change_owner_role}
  def allow_role_change(%{role: "owner"}), do: {:error, :cannot_change_owner_role}
  def allow_role_change(_membership), do: :ok

  @spec allow_removal(map()) :: :ok | {:error, :cannot_remove_owner}
  def allow_removal(%{role: "owner"}), do: {:error, :cannot_remove_owner}
  def allow_removal(_membership), do: :ok
end
