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
      data-translations={Jason.encode!(@translations)}
      class="instruction-builder"
    >
    </div>
    """
  end

  defp translations do
    %{
      operator_verbs: %{
        "set" => gettext("Set"),
        "add" => gettext("Add"),
        "subtract" => gettext("Subtract"),
        "set_true" => gettext("Set"),
        "set_false" => gettext("Set"),
        "toggle" => gettext("Toggle"),
        "clear" => gettext("Clear")
      },
      operator_dropdown_labels: %{
        "set" => gettext("Set \u2026 to"),
        "add" => gettext("Add \u2026 to"),
        "subtract" => gettext("Subtract \u2026 from"),
        "set_true" => gettext("Set \u2026 to true"),
        "set_false" => gettext("Set \u2026 to false"),
        "toggle" => gettext("Toggle"),
        "clear" => gettext("Clear")
      },
      sentence_texts: %{
        "to" => gettext("to"),
        "from" => gettext("from"),
        "to true" => gettext("to true"),
        "to false" => gettext("to false")
      },
      add_assignment: gettext("Add assignment"),
      no_assignments: gettext("No assignments"),
      placeholder_sheet: gettext("sheet"),
      placeholder_variable: gettext("variable"),
      placeholder_value: gettext("value"),
      switch_to_literal: gettext("Switch to literal value"),
      switch_to_variable_ref: gettext("Switch to variable reference")
    }
  end
end
