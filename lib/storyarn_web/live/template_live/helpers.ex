defmodule StoryarnWeb.TemplateLive.Helpers do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  def template_description(%{description: description}) when is_binary(description) and description != "" do
    description
  end

  def template_description(_template), do: dgettext("projects", "No description")

  def visibility_label("public"), do: dgettext("projects", "Public")
  def visibility_label(_visibility), do: dgettext("projects", "Private")

  def visibility_badge_class("public"), do: "badge-info"
  def visibility_badge_class(_visibility), do: "badge-outline"

  def status_label("archived"), do: dgettext("projects", "Archived")
  def status_label(_status), do: dgettext("projects", "Active")

  def publication_status_label("queued"), do: dgettext("projects", "Queued")
  def publication_status_label("running"), do: dgettext("projects", "Publishing")
  def publication_status_label("retrying"), do: dgettext("projects", "Retrying")
  def publication_status_label("published"), do: dgettext("projects", "Published")
  def publication_status_label("failed"), do: dgettext("projects", "Failed")
  def publication_status_label(_status), do: dgettext("projects", "Unknown")

  def publication_badge_class("published"), do: "badge-success"
  def publication_badge_class("failed"), do: "badge-error"
  def publication_badge_class("retrying"), do: "badge-warning"
  def publication_badge_class(status) when status in ~w(queued running), do: "badge-info"
  def publication_badge_class(_status), do: "badge-outline"

  def version_label(%{version_number: version_number}) when is_integer(version_number) do
    dgettext("projects", "Version %{version}", version: version_number)
  end

  def version_label(_version), do: dgettext("projects", "No version")

  def format_datetime(nil), do: ""

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  def format_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> format_datetime()
  end
end
