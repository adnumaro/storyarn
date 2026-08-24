defmodule Storyarn.Billing.Persistence.ProjectTemplateVersionRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_template_versions" do
    field :project_template_id, :id

    timestamps(type: :utc_datetime)
  end
end
