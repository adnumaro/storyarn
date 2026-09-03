defmodule Storyarn.Projects.Assets.StorageCleanupOwnershipReceipt do
  @moduledoc """
  Immutable proof that an exact object inventory was handed to durable cleanup.

  Rows are captured by a database trigger when a mutable cleanup request is
  inserted. They deliberately survive request completion and rotation so a
  storage reservation can verify its original handoff without depending on a
  live queue row.
  """
  use Ecto.Schema

  @primary_key {:cleanup_request_id, :integer, autogenerate: false}
  schema "storage_cleanup_ownership_receipts" do
    field :storage_keys, {:array, :string}
    field :recorded_at, :utc_datetime
  end
end
