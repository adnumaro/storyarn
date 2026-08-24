defmodule Storyarn.Billing.Persistence.ProjectTemplateRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_templates" do
    field :source_project_id, :id

    timestamps(type: :utc_datetime)
  end
end
