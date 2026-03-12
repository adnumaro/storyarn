defmodule StoryarnWeb.Live.Shared.RestorationHandlers do
  @moduledoc """
  Shared `handle_info` clauses for project restoration lock events.

  Subscribes via `Collaboration.subscribe_restoration/1` in mount, then
  handles restoration lifecycle messages:

  - `:project_restoration_started` → disable editing, show banner
  - `:project_restoration_completed` → push_navigate to reload with fresh data
  - `:project_restoration_failed` → restore editing, clear banner, flash error

  ## Usage

      use StoryarnWeb.Live.Shared.RestorationHandlers

  The using module must have `:project`, `:workspace`, `:membership`, and
  `:can_edit` assigns. Set `:restoration_banner` to `nil` in mount defaults.

  The macro also imports `check_restoration_lock/2` for use in mount.
  """

  @doc """
  Checks if a restoration is in progress and adjusts can_edit + banner accordingly.

  Returns `{can_edit, restoration_banner}`.
  """
  def check_restoration_lock(project_id, can_edit) do
    case Storyarn.Projects.restoration_in_progress?(project_id) do
      {true, %{user_id: user_id}} ->
        email = restoration_user_email(user_id)
        {false, %{user_email: email}}

      _ ->
        {can_edit, nil}
    end
  end

  defp restoration_user_email(nil), do: "another user"

  defp restoration_user_email(user_id) do
    Storyarn.Accounts.get_user!(user_id).email
  rescue
    Ecto.NoResultsError -> "another user"
  end

  defmacro __using__(_opts) do
    quote do
      import StoryarnWeb.Live.Shared.RestorationHandlers, only: [check_restoration_lock: 2]

      @impl true
      def handle_info({:project_restoration_started, payload}, socket) do
        {:noreply,
         socket
         |> Phoenix.Component.assign(:can_edit, false)
         |> Phoenix.Component.assign(:restoration_banner, %{
           user_email: payload[:user_email] || "another user"
         })}
      end

      @impl true
      def handle_info({:project_restoration_completed, _payload}, socket) do
        path =
          "/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}"

        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(
           :info,
           Gettext.dgettext(StoryarnWeb.Gettext, "projects", "Project restored successfully.")
         )
         |> Phoenix.LiveView.push_navigate(to: path)}
      end

      @impl true
      def handle_info({:project_restoration_failed, _payload}, socket) do
        can_edit =
          case socket.assigns[:membership] do
            %{role: role} -> Storyarn.Projects.can?(role, :edit_content)
            _ -> false
          end

        {:noreply,
         socket
         |> Phoenix.Component.assign(:can_edit, can_edit)
         |> Phoenix.Component.assign(:restoration_banner, nil)
         |> Phoenix.LiveView.put_flash(
           :error,
           Gettext.dgettext(
             StoryarnWeb.Gettext,
             "projects",
             "Project restoration failed. Please try again."
           )
         )}
      end

      defoverridable handle_info: 2
    end
  end
end
