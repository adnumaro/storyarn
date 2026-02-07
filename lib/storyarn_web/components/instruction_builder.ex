defmodule StoryarnWeb.Components.InstructionBuilder do
  @moduledoc """
  Thin HEEx wrapper that renders the InstructionBuilder JS hook container.

  The JS hook owns the assignments array client-side and pushes changes
  via `pushEvent("update_instruction_builder", %{assignments: [...]})`.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :assignments, :list, default: []
  attr :variables, :list, default: []
  attr :can_edit, :boolean, default: true

  def instruction_builder(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="InstructionBuilder"
      phx-update="ignore"
      data-assignments={Jason.encode!(@assignments)}
      data-variables={Jason.encode!(@variables)}
      data-can-edit={Jason.encode!(@can_edit)}
      class="instruction-builder"
    >
    </div>
    """
  end
end
