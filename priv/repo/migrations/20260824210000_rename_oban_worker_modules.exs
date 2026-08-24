defmodule Storyarn.Repo.Migrations.RenameObanWorkerModules do
  use Ecto.Migration

  @moduledoc """
  ENG-92 physical reorganization: Oban persists worker module names, so queued
  and historical jobs must follow the Storyarn.Workers.* renames into their
  owning bounded contexts.
  """

  @renames [
    {"Storyarn.Workers.AIExecutionWorker", "Storyarn.AI.Workers.AIExecutionWorker"},
    {"Storyarn.Workers.BuildProjectSnapshotWorker",
     "Storyarn.Projects.Workers.BuildProjectSnapshotWorker"},
    {"Storyarn.Workers.CleanupProjectSnapshotWorker",
     "Storyarn.Projects.Workers.CleanupProjectSnapshotWorker"},
    {"Storyarn.Workers.DeleteProjectTemplateArtifactsWorker",
     "Storyarn.Projects.Workers.DeleteProjectTemplateArtifactsWorker"},
    {"Storyarn.Workers.DeleteStorageObjectsWorker",
     "Storyarn.Projects.Workers.DeleteStorageObjectsWorker"},
    {"Storyarn.Workers.DeliverInvitationWorker",
     "Storyarn.Platform.Workers.DeliverInvitationWorker"},
    {"Storyarn.Workers.DeliverResetPasswordInstructionsWorker",
     "Storyarn.Accounts.Workers.DeliverResetPasswordInstructionsWorker"},
    {"Storyarn.Workers.ExpireAIResultsWorker", "Storyarn.AI.Workers.ExpireAIResultsWorker"},
    {"Storyarn.Workers.ExpireProjectImportsWorker",
     "Storyarn.Projects.Workers.ExpireProjectImportsWorker"},
    {"Storyarn.Workers.ImportProjectSnapshotWorker",
     "Storyarn.Projects.Workers.ImportProjectSnapshotWorker"},
    {"Storyarn.Workers.ImportProjectWorker", "Storyarn.Projects.Workers.ImportProjectWorker"},
    {"Storyarn.Workers.InspectProjectSnapshotsWorker",
     "Storyarn.Projects.Workers.InspectProjectSnapshotsWorker"},
    {"Storyarn.Workers.InstallProjectTemplateWorker",
     "Storyarn.Projects.Workers.InstallProjectTemplateWorker"},
    {"Storyarn.Workers.LocalizationBatchTranslationWorker",
     "Storyarn.Localization.Workers.LocalizationBatchTranslationWorker"},
    {"Storyarn.Workers.ProjectSnapshotRetentionWorker",
     "Storyarn.Projects.Workers.ProjectSnapshotRetentionWorker"},
    {"Storyarn.Workers.PublishProjectTemplateWorker",
     "Storyarn.Projects.Workers.PublishProjectTemplateWorker"},
    {"Storyarn.Workers.ReconcileAIReservationsWorker",
     "Storyarn.AI.Workers.ReconcileAIReservationsWorker"},
    {"Storyarn.Workers.ReconcileProjectSnapshotCleanupWorker",
     "Storyarn.Projects.Workers.ReconcileProjectSnapshotCleanupWorker"},
    {"Storyarn.Workers.ReconcileProjectSnapshotRepairWorker",
     "Storyarn.Projects.Workers.ReconcileProjectSnapshotRepairWorker"},
    {"Storyarn.Workers.RepairProjectSnapshotFindingWorker",
     "Storyarn.Projects.Workers.RepairProjectSnapshotFindingWorker"},
    {"Storyarn.Workers.RequestResetPasswordInstructionsWorker",
     "Storyarn.Accounts.Workers.RequestResetPasswordInstructionsWorker"},
    {"Storyarn.Workers.RestoreProjectSnapshotWorker",
     "Storyarn.Projects.Workers.RestoreProjectSnapshotWorker"},
    {"Storyarn.Workers.RetryStorageCleanupRequestsWorker",
     "Storyarn.Projects.Workers.RetryStorageCleanupRequestsWorker"},
    {"Storyarn.Workers.TrashRetentionWorker", "Storyarn.Projects.Workers.TrashRetentionWorker"}
  ]

  def up do
    for {old, new} <- @renames do
      execute("UPDATE oban_jobs SET worker = '#{new}' WHERE worker = '#{old}'")
    end
  end

  def down do
    for {old, new} <- @renames do
      execute("UPDATE oban_jobs SET worker = '#{old}' WHERE worker = '#{new}'")
    end
  end
end
