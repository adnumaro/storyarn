defmodule Storyarn.AI.PersonalRolesTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.ModelCatalog.Entry
  alias Storyarn.AI.PersonalRoles

  test "keeps general tasks separate from narrative writing suggestions" do
    assert PersonalRoles.visible() ==
             [:general_assistant, :writing_assistant, :illustrator, :voice]

    assert PersonalRoles.role_for_capability(:tasks) == :general_assistant
    assert PersonalRoles.role_for_capability(:suggestions) == :writing_assistant
    assert PersonalRoles.role_for_capability(:images) == :illustrator
    assert PersonalRoles.role_for_capability(:speech) == :voice
    assert PersonalRoles.role_for_capability(:translation) == :translator
  end

  test "a model must explicitly declare the capability required by its role" do
    task_model = entry!(:tasks)
    suggestion_model = entry!(:suggestions)

    assert PersonalRoles.assignable?(:general_assistant, task_model)
    refute PersonalRoles.assignable?(:writing_assistant, task_model)

    assert PersonalRoles.assignable?(:writing_assistant, suggestion_model)
    refute PersonalRoles.assignable?(:general_assistant, suggestion_model)
  end

  defp entry!(capability) do
    assert {:ok, entry} =
             Entry.new(%{
               provider: "openai",
               model: "only-#{capability}",
               catalog_version: 1,
               capabilities: [capability],
               input_modalities: [:text],
               output_modalities: [:text],
               structured_output: :json_schema,
               api_family: :structured_text,
               implementation_status: :executable,
               release_stage: :stable,
               context_window: 1_024,
               max_output_tokens: 512,
               processing_locations: ["provider-controlled"],
               pricing_version: nil,
               deprecated: false
             })

    entry
  end
end
