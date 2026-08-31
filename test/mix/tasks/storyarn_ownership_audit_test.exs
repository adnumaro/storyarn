defmodule Mix.Tasks.Storyarn.Ownership.AuditTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Storyarn.Ownership.Audit

  test "does not start Storyarn.Application, Oban or their dependency closure" do
    requirements =
      :attributes
      |> Audit.__info__()
      |> Keyword.get_values(:requirements)
      |> List.flatten()

    refute "app.start" in requirements

    applications = Audit.runtime_applications()
    refute :storyarn in applications
    refute :oban in applications

    closure = application_dependency_closure(applications)
    refute :storyarn in closure
    refute :oban in closure
  end

  defp application_dependency_closure(applications) do
    visit_applications(applications, MapSet.new())
  end

  defp visit_applications([], visited), do: MapSet.to_list(visited)

  defp visit_applications([application | rest], visited) do
    if MapSet.member?(visited, application) do
      visit_applications(rest, visited)
    else
      dependencies =
        List.wrap(Application.spec(application, :applications)) ++
          List.wrap(Application.spec(application, :included_applications))

      visit_applications(rest ++ dependencies, MapSet.put(visited, application))
    end
  end
end
