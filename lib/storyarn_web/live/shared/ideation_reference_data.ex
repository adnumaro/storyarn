defmodule StoryarnWeb.Live.Shared.IdeationReferenceData do
  @moduledoc false
  use StoryarnWeb, :verified_routes

  @overview_fields ~w(shortcut description color is_main width height filename content_type size locale_code source_type source_field source_text translated_text status)

  def reference(row, socket) do
    %{
      id: row.id,
      version: row.version,
      relation: row.relation,
      targetType: row.target_type,
      targetId: row.target_id,
      status: row.status,
      base: base(row.base),
      current: if(row.current, do: target(row.current, socket)),
      capturedAt: row.captured_at
    }
  end

  def base(nil), do: nil

  def base(context) do
    %{name: context["name"], fields: fields(context["overview"] || %{}), capturedAt: context["captured_at"]}
  end

  def target(target, socket) do
    %{
      id: target.id,
      type: target.type,
      name: target.name,
      fields: fields(target.context),
      href: destination(target.locator, socket)
    }
  end

  defp fields(context) do
    for key <- @overview_fields,
        value <- [context[key]],
        not is_nil(value) and value != "" do
      %{key: key, value: to_string(value), truncated: context[key <> "_truncated"] == true}
    end
  end

  def destination(%{type: "sheet", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/sheets/#{id}"

  def destination(%{type: "flow", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{id}"

  def destination(%{type: "scene", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/scenes/#{id}"

  def destination(%{type: "asset", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/assets?#{%{asset: id}}"

  def destination(%{type: "localization", id: id}, %{assigns: assigns}),
    do: ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/localization/text/#{id}"

  def destination(_, _), do: nil
end
