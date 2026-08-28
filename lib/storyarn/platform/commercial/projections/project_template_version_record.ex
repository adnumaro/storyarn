defmodule Storyarn.Platform.Billing.Persistence.ProjectTemplateVersionRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_template_versions" do
    field :project_template_id, :id

    timestamps(type: :utc_datetime)
  end
end
