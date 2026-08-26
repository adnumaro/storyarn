defmodule Storyarn.Architecture.AIProjectionAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.AllowanceLedgerEntry
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.AuditEntry
  alias Storyarn.AI.Governance.Data.UserRecord, as: GovernanceUserRecord
  alias Storyarn.AI.Governance.Data.WorkspaceRecord, as: GovernanceWorkspaceRecord
  alias Storyarn.AI.Integration
  alias Storyarn.AI.Integrations.Data.UserRecord, as: IntegrationsUserRecord
  alias Storyarn.AI.Integrations.Data.WorkspaceRecord, as: IntegrationsWorkspaceRecord
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.AI.ManagedSpend.Data.UserRecord, as: ManagedSpendUserRecord
  alias Storyarn.AI.ManagedSpend.Data.WorkspaceRecord, as: ManagedSpendWorkspaceRecord
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations.Data.ProjectRecord, as: OperationsProjectRecord
  alias Storyarn.AI.Operations.Data.UserRecord, as: OperationsUserRecord
  alias Storyarn.AI.Operations.Data.WorkspaceRecord, as: OperationsWorkspaceRecord
  alias Storyarn.AI.OperatorAlert
  alias Storyarn.AI.PersonalConsent
  alias Storyarn.AI.PersonalPreference
  alias Storyarn.AI.ProviderBudgetReservation
  alias Storyarn.AI.Result
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.Routing.Data.ProjectRecord, as: RoutingProjectRecord
  alias Storyarn.AI.Routing.Data.UserRecord, as: RoutingUserRecord
  alias Storyarn.AI.Routing.Data.WorkspaceRecord, as: RoutingWorkspaceRecord
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.AI.WorkspacePolicyAudit

  test "AI-owned records associate foreign identities to their capability-local projections" do
    assert association(WorkspacePolicy, :workspace) == GovernanceWorkspaceRecord
    assert association(WorkspacePolicy, :updated_by) == GovernanceUserRecord
    assert association(WorkspacePolicyAudit, :workspace) == GovernanceWorkspaceRecord
    assert association(WorkspacePolicyAudit, :user) == GovernanceUserRecord

    assert association(Integration, :user) == IntegrationsUserRecord
    assert association(IntegrationWorkspaceAssignment, :user) == IntegrationsUserRecord
    assert association(IntegrationWorkspaceAssignment, :workspace) == IntegrationsWorkspaceRecord
    assert association(PersonalConsent, :user) == IntegrationsUserRecord
    assert association(PersonalConsent, :workspace) == IntegrationsWorkspaceRecord
    assert association(PersonalPreference, :user) == IntegrationsUserRecord
    assert association(PersonalPreference, :workspace) == IntegrationsWorkspaceRecord
    assert association(AuditEntry, :user) == IntegrationsUserRecord

    assert association(AllowanceAccount, :workspace) == ManagedSpendWorkspaceRecord
    assert association(AllowanceGrant, :workspace) == ManagedSpendWorkspaceRecord
    assert association(AllowanceGrant, :granted_by) == ManagedSpendUserRecord
    assert association(AllowanceReservation, :workspace) == ManagedSpendWorkspaceRecord
    assert association(AllowanceLedgerEntry, :workspace) == ManagedSpendWorkspaceRecord
    assert association(ProviderBudgetReservation, :workspace) == ManagedSpendWorkspaceRecord

    assert association(Operation, :user) == OperationsUserRecord
    assert association(Operation, :workspace) == OperationsWorkspaceRecord
    assert association(Operation, :project) == OperationsProjectRecord
    assert association(Result, :user) == OperationsUserRecord
    assert association(Result, :workspace) == OperationsWorkspaceRecord
    assert association(Result, :project) == OperationsProjectRecord
    assert association(OperatorAlert, :workspace) == OperationsWorkspaceRecord

    assert association(RouteOption, :user) == RoutingUserRecord
    assert association(RouteOption, :workspace) == RoutingWorkspaceRecord
    assert association(RouteOption, :project) == RoutingProjectRecord
  end

  test "AI projections and owned records do not import foreign context schemas" do
    violations =
      for role <- ~w(data entities events),
          path <- Path.wildcard("lib/storyarn/ai/*/#{role}/**/*.ex"),
          reference <- foreign_context_references(path),
          do: "#{path}: #{reference}"

    assert violations == [],
           "AI projections must duplicate the read shape they need instead of importing foreign schemas: #{inspect(violations)}"
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related

  defp foreign_context_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, _, [:Storyarn, context | _rest] = segments} = node, references
        when context in [:Accounts, :Projects, :Workspaces] ->
          {node, [Enum.join(segments, ".") | references]}

        node, references ->
          {node, references}
      end)

    Enum.uniq(references)
  end
end
