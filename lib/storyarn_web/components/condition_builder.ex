defmodule StoryarnWeb.Components.ConditionBuilder do
  @moduledoc """
  Thin wrapper that renders a `phx-hook="ConditionBuilder"` element.

  All UI logic lives in `assets/js/hooks/condition_builder.js`.
  The hook reads initial state from `data-*` attributes and pushes
  the full condition back on every change.

  Translations are passed via `data-translations` so the JS hook
  can render localized operator labels and UI strings.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows.Condition

  @doc """
  Renders the condition builder hook container.
  """
  attr :id, :string, required: true
  attr :condition, :map, default: nil
  attr :variables, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :context, :map, default: %{}
  attr :switch_mode, :boolean, default: false
  attr :event_name, :string, default: nil

  def condition_builder(assigns) do
    parsed_condition =
      case assigns.condition do
        nil -> Condition.new()
        %{"logic" => _, "blocks" => _} = cond -> cond
        %{"logic" => _, "rules" => _} = cond -> cond
        :legacy -> Condition.new()
        _string -> Condition.new()
      end

    assigns =
      assigns
      |> assign(:parsed_condition, parsed_condition)
      |> assign(:translations, translations())

    ~H"""
    <div
      id={@id}
      phx-hook="ConditionBuilder"
      phx-update="ignore"
      data-condition={Jason.encode!(@parsed_condition)}
      data-variables={Jason.encode!(@variables)}
      data-can-edit={Jason.encode!(@can_edit)}
      data-switch-mode={Jason.encode!(@switch_mode)}
      data-context={Jason.encode!(@context)}
      data-event-name={@event_name}
      data-translations={Jason.encode!(@translations)}
      class="condition-builder"
    >
    </div>
    """
  end

  @doc false
  def translations do
    %{
      operator_labels: %{
        "equals" => dgettext("flows", "equals"),
        "not_equals" => dgettext("flows", "not equals"),
        "contains" => dgettext("flows", "contains"),
        "starts_with" => dgettext("flows", "starts with"),
        "ends_with" => dgettext("flows", "ends with"),
        "is_empty" => dgettext("flows", "is empty"),
        "greater_than" => dgettext("flows", "greater than"),
        "greater_than_or_equal" => dgettext("flows", "greater than or equal"),
        "less_than" => dgettext("flows", "less than"),
        "less_than_or_equal" => dgettext("flows", "less than or equal"),
        "is_true" => dgettext("flows", "is true"),
        "is_false" => dgettext("flows", "is false"),
        "is_nil" => dgettext("flows", "is not set"),
        "not_contains" => dgettext("flows", "does not contain"),
        "before" => dgettext("flows", "before"),
        "after" => dgettext("flows", "after")
      },
      match: dgettext("flows", "Match"),
      all: dgettext("flows", "all"),
      any: dgettext("flows", "any"),
      of_the_rules: dgettext("flows", "of the rules"),
      of_the_blocks: dgettext("flows", "of the blocks"),
      switch_mode_info: dgettext("flows", "Each condition creates an output. First match wins."),
      add_condition: dgettext("flows", "Add condition"),
      add_block: dgettext("flows", "Add block"),
      group: dgettext("flows", "Group"),
      group_selected: dgettext("flows", "Group selected"),
      cancel: dgettext("flows", "Cancel"),
      ungroup: dgettext("flows", "Ungroup"),
      no_conditions: dgettext("flows", "No conditions set"),
      placeholder_sheet: dgettext("flows", "sheet"),
      placeholder_variable: dgettext("flows", "variable"),
      placeholder_operator: dgettext("flows", "op"),
      placeholder_value: dgettext("flows", "value"),
      placeholder_label: dgettext("flows", "label")
    }
  end
end
