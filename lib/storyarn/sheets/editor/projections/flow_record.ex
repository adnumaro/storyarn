defmodule Storyarn.Sheets.Editor.Projections.FlowRecord do
  @moduledoc """
  Flow identity read by the Sheet editor's dialogue-audio workspace.

  Sheets does not own Flow lifecycle; this projection exists only to scope and
  present dialogue nodes spoken by a Sheet.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flows" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :position, :integer, default: 0
    field :is_main, :boolean, default: false
    field :settings, :map, default: %{}
    field :project_id, :id
    field :scene_id, :id
    field :current_version_id, :id
    field :deleted_at, :utc_datetime
    field :parent_id, :id

    timestamps(type: :utc_datetime)
  end
end
