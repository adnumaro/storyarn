defmodule Storyarn.Projects.Imports.FormatReview do
  @moduledoc """
  Parser-independent entry point for source-format review policy.

  Unknown formats fail closed. The shared lifecycle must never infer that a
  format needs no review merely because it does not know that format.
  """

  alias Storyarn.Projects.Imports.FormatRegistry
  alias Storyarn.Projects.Imports.ImportPlan

  @spec ensure_supported(ImportPlan.t()) :: :ok | {:error, :unsupported_import_format}
  def ensure_supported(%ImportPlan{} = plan) do
    with {:ok, _adapter} <- FormatRegistry.compatible_adapter(plan), do: :ok
  end

  @spec ensure_resolved(ImportPlan.t()) :: :ok | {:error, :invalid_import_review | :unsupported_import_format}
  def ensure_resolved(%ImportPlan{} = plan) do
    with {:ok, adapter} <- FormatRegistry.compatible_adapter(plan) do
      if adapter.review_resolved?(plan), do: :ok, else: {:error, :invalid_import_review}
    end
  end

  @spec put_allowed_actions(ImportPlan.t(), term()) ::
          {:ok, map()} | {:error, :invalid_import_review | :unsupported_import_format}
  def put_allowed_actions(%ImportPlan{} = plan, review) do
    with {:ok, adapter} <- FormatRegistry.compatible_adapter(plan),
         true <- is_map(review) do
      {:ok, adapter.put_allowed_review_actions(review)}
    else
      false -> {:error, :invalid_import_review}
      {:error, _reason} = error -> error
    end
  end

  @spec save_draft(ImportPlan.t(), term()) :: {:ok, ImportPlan.t()} | {:error, term()}
  def save_draft(%ImportPlan{} = plan, decisions) do
    with {:ok, adapter} <- FormatRegistry.compatible_adapter(plan) do
      plan
      |> adapter.save_review_draft(decisions)
      |> validate_callback_revision(plan)
    end
  end

  @spec apply(ImportPlan.t(), boolean(), term()) :: {:ok, ImportPlan.t()} | {:error, term()}
  def apply(%ImportPlan{} = plan, acknowledged?, decisions) do
    with {:ok, adapter} <- FormatRegistry.compatible_adapter(plan) do
      plan
      |> adapter.apply_review(acknowledged?, decisions)
      |> validate_callback_revision(plan)
    end
  end

  @spec confirmation_fingerprint(ImportPlan.t()) :: {:ok, String.t()} | {:error, term()}
  def confirmation_fingerprint(%ImportPlan{} = plan) do
    with {:ok, adapter} <- FormatRegistry.compatible_adapter(plan) do
      adapter.confirmation_fingerprint(plan)
    end
  end

  @spec confirm(ImportPlan.t(), term()) :: :ok | {:error, term()}
  def confirm(%ImportPlan{} = plan, fingerprint) do
    with {:ok, adapter} <- FormatRegistry.compatible_adapter(plan) do
      adapter.confirm_review(plan, fingerprint)
    end
  end

  @doc false
  @spec validate_revision(ImportPlan.t(), ImportPlan.t()) :: :ok | {:error, :invalid_import_review}
  def validate_revision(%ImportPlan{} = original, %ImportPlan{} = revised) do
    original_identity = original |> Map.from_struct() |> Map.delete(:data)
    revised_identity = revised |> Map.from_struct() |> Map.delete(:data)

    if original_identity == revised_identity,
      do: :ok,
      else: {:error, :invalid_import_review}
  end

  defp validate_callback_revision({:ok, %ImportPlan{} = revised}, original) do
    with :ok <- validate_revision(original, revised), do: {:ok, revised}
  end

  defp validate_callback_revision({:error, _reason} = error, _original), do: error
  defp validate_callback_revision(_unexpected, _original), do: {:error, :invalid_import_review}
end
