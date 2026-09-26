defmodule StoryarnWeb.Live.Shared.ReadOnlyNotice do
  @moduledoc """
  What people see while a workspace is read-only: its owner's account is over
  its plan's limits.

  The owner learns which limits the account exceeds and gets the link to Plan
  & billing. Everyone else who could edit is told whom to ask, and nothing
  about the plan. Viewers see nothing new: they could not edit before either.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts
  alias Storyarn.Commercial
  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.Live.Shared.PlanLimitFlash
  alias StoryarnWeb.Live.Shared.UsageAccess

  @editing_workspace_roles ~w(owner admin member)

  @doc "Whether the workspace is read-only."
  @spec read_only?(pos_integer()) :: boolean()
  def read_only?(workspace_id) when is_integer(workspace_id),
    do: Commercial.workspace_read_only_reasons(workspace_id) != []

  @doc """
  The banner of a project's shell while its workspace is read-only, for those
  whose project role could edit it; nil otherwise.
  """
  @spec project_banner(map(), map(), String.t() | nil) :: map() | nil
  def project_banner(scope, %{id: _, owner_id: _} = workspace, project_role) do
    if Projects.can?(project_role, :edit_content), do: banner(scope, workspace)
  end

  @doc "The banner of a workspace's shell, for its owner, admins and members; nil otherwise."
  @spec workspace_banner(map() | nil, map() | nil) :: map() | nil
  def workspace_banner(%{user: _} = scope, %{id: workspace_id, owner_id: _} = workspace) do
    case Workspaces.authorize(scope, workspace_id, :view) do
      {:ok, _workspace, %{role: role}} when role in @editing_workspace_roles -> banner(scope, workspace)
      _other -> nil
    end
  end

  def workspace_banner(_scope, _workspace), do: nil

  @doc """
  Tells the actor that the workspace is read-only, after it refused their
  action.
  """
  @spec put_flash(Socket.t()) :: Socket.t()
  def put_flash(%Socket{assigns: %{current_scope: scope} = assigns} = socket) do
    case workspace(assigns) do
      %{id: workspace_id} = workspace -> PlanLimitFlash.put(socket, workspace_id, message(scope, workspace))
      nil -> Phoenix.LiveView.put_flash(socket, :error, gettext("This workspace is read-only."))
    end
  end

  @doc """
  Tells the actor that their own account is over its plan's limits, after it
  refused to add a workspace to it.
  """
  @spec put_account_flash(Socket.t()) :: Socket.t()
  def put_account_flash(%Socket{assigns: %{current_scope: scope}} = socket) do
    Phoenix.LiveView.put_flash(socket, :limit, %{
      "message" =>
        gettext(
          "Your account is over its plan's limits, so you cannot create workspaces. Upgrade your plan, or delete what you no longer need."
        ),
      "planPath" => UsageAccess.plan_path(scope, %{owner_id: scope.user.id})
    })
  end

  @doc """
  Same as `put_flash/1`, from a sticky sidebar: its flash never reaches the
  toaster, so the page that renders it shows the notice.
  """
  @spec forward(Socket.t()) :: Socket.t()
  def forward(%Socket{assigns: %{current_scope: scope} = assigns} = socket) do
    message =
      case workspace(assigns) do
        %{id: _} = workspace -> message(scope, workspace)
        nil -> gettext("This workspace is read-only.")
      end

    PlanLimitFlash.forward(socket, message)
  end

  @doc "The notice's text: why and what to do for the owner, whom to ask for everyone else."
  @spec message(map(), map()) :: String.t()
  def message(scope, workspace) do
    if owner?(scope, workspace) do
      gettext(
        "This workspace is read-only because your account is over its plan's limits. Upgrade your plan, or delete what you no longer need."
      )
    else
      gettext("This workspace is read-only. Contact its owner, %{owner}, to edit it again.",
        owner: owner_name(workspace)
      )
    end
  end

  defp banner(scope, workspace) do
    case Commercial.workspace_read_only_reasons(workspace.id) do
      [] ->
        nil

      reasons ->
        if owner?(scope, workspace),
          do: %{owner: true, reasons: reasons, planPath: UsageAccess.plan_path(scope, workspace)},
          else: %{owner: false, ownerName: owner_name(workspace)}
    end
  end

  defp owner?(%{user: %{id: user_id}}, %{owner_id: user_id}), do: true
  defp owner?(_scope, _workspace), do: false

  defp owner_name(%{owner_id: owner_id}) do
    owner = Accounts.get_user!(owner_id)
    owner.display_name || owner.email
  end

  defp workspace(%{workspace: %{id: _, owner_id: _} = workspace}), do: workspace
  defp workspace(%{current_workspace: %{id: _, owner_id: _} = workspace}), do: workspace

  defp workspace(%{project: %{workspace_id: workspace_id}}) when is_integer(workspace_id),
    do: Workspaces.get_workspace!(workspace_id)

  defp workspace(%{workspace_id: workspace_id}) when is_integer(workspace_id),
    do: Workspaces.get_workspace!(workspace_id)

  defp workspace(_assigns), do: nil
end
