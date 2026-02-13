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
        "equals" => gettext("equals"),
        "not_equals" => gettext("not equals"),
        "contains" => gettext("contains"),
        "starts_with" => gettext("starts with"),
        "ends_with" => gettext("ends with"),
        "is_empty" => gettext("is empty"),
        "greater_than" => gettext("greater than"),
        "greater_than_or_equal" => gettext("greater than or equal"),
        "less_than" => gettext("less than"),
        "less_than_or_equal" => gettext("less than or equal"),
        "is_true" => gettext("is true"),
        "is_false" => gettext("is false"),
        "is_nil" => gettext("is not set"),
        "not_contains" => gettext("does not contain"),
        "before" => gettext("before"),
        "after" => gettext("after")
      },
      match: gettext("Match"),
      all: gettext("all"),
      any: gettext("any"),
      of_the_rules: gettext("of the rules"),
      switch_mode_info: gettext("Each condition creates an output. First match wins."),
      add_condition: gettext("Add condition"),
      no_conditions: gettext("No conditions set"),
      placeholder_sheet: gettext("sheet"),
      placeholder_variable: gettext("variable"),
      placeholder_operator: gettext("op"),
      placeholder_value: gettext("value"),
      placeholder_label: gettext("label")
    }
  end
end
