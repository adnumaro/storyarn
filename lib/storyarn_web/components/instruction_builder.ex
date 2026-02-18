defmodule StoryarnWeb.Components.InstructionBuilder do
  @moduledoc """
  Thin HEEx wrapper that renders the InstructionBuilder JS hook container.

  The JS hook owns the assignments array client-side and pushes changes
  via `pushEvent("update_instruction_builder", %{assignments: [...]})`.

  Translations are passed via `data-translations` so the JS hook
  can render localized operator labels and UI strings.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  attr :id, :string, required: true
  attr :assignments, :list, default: []
  attr :variables, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :context, :map, default: %{}
  attr :event_name, :string, default: nil

  def instruction_builder(assigns) do
    assigns = assign(assigns, :translations, translations())

    ~H"""
    <div
      id={@id}
      phx-hook="InstructionBuilder"
      phx-update="ignore"
      data-assignments={Jason.encode!(@assignments)}
      data-variables={Jason.encode!(@variables)}
      data-can-edit={Jason.encode!(@can_edit)}
      data-context={Jason.encode!(@context)}
      data-event-name={@event_name}
      data-translations={Jason.encode!(@translations)}
      class="instruction-builder"
    >
    </div>
    """
  end

  @doc false
  def translations do
    %{
      operator_verbs: %{
        "set" => dgettext("flows", "Set"),
        "add" => dgettext("flows", "Add"),
        "subtract" => dgettext("flows", "Subtract"),
        "set_true" => dgettext("flows", "Set"),
        "set_false" => dgettext("flows", "Set"),
        "toggle" => dgettext("flows", "Toggle"),
        "clear" => dgettext("flows", "Clear")
      },
      operator_dropdown_labels: %{
        "set" => dgettext("flows", "Set \u2026 to"),
        "add" => dgettext("flows", "Add \u2026 to"),
        "subtract" => dgettext("flows", "Subtract \u2026 from"),
        "set_true" => dgettext("flows", "Set \u2026 to true"),
        "set_false" => dgettext("flows", "Set \u2026 to false"),
        "toggle" => dgettext("flows", "Toggle"),
        "clear" => dgettext("flows", "Clear")
      },
      sentence_texts: %{
        "to" => dgettext("flows", "to"),
        "from" => dgettext("flows", "from"),
        "to true" => dgettext("flows", "to true"),
        "to false" => dgettext("flows", "to false")
      },
      add_assignment: dgettext("flows", "Add assignment"),
      no_assignments: dgettext("flows", "No assignments"),
      placeholder_sheet: dgettext("flows", "sheet"),
      placeholder_variable: dgettext("flows", "variable"),
      placeholder_value: dgettext("flows", "value"),
      switch_to_literal: dgettext("flows", "Switch to literal value"),
      switch_to_variable_ref: dgettext("flows", "Switch to variable reference")
    }
  end
end
