defmodule StoryarnWeb.Components.MemberComponents do
  @moduledoc """
  Shared components for displaying team members and invitations.

  These components are used in both project and workspace settings pages.
  """
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.UIComponents

  @doc """
  Renders a user avatar with initials fallback.

  ## Examples

      <.user_avatar user={@member.user} />
      <.user_avatar email="user@example.com" />
  """
  attr :user, :map, default: nil
  attr :email, :string, default: nil
  attr :size, :string, default: "md", values: ["sm", "md", "lg"]

  def user_avatar(assigns) do
    email = assigns[:email] || (assigns[:user] && assigns[:user].email) || ""
    initials = get_initials_from_email(email)
    assigns = assign(assigns, :initials, initials)

    ~H"""
    <div class="avatar placeholder">
      <div class={[
        "bg-neutral text-neutral-content rounded-full",
        @size == "sm" && "size-8",
        @size == "md" && "size-10",
        @size == "lg" && "size-12"
      ]}>
        <span class={[
          @size == "sm" && "text-xs",
          @size == "md" && "text-sm",
          @size == "lg" && "text-base"
        ]}>
          {@initials}
        </span>
      </div>
    </div>
    """
  end

  defp get_initials_from_email(email_or_name) when is_binary(email_or_name) do
    email_or_name
    |> String.split(~r/[@\s]/)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp get_initials_from_email(_), do: "?"

  @doc """
  Renders a member row for project or workspace member lists.

  ## Examples

      <.member_row
        member={@member}
        current_user_id={@current_scope.user.id}
        on_remove="remove_member"
      />

      <.member_row
        member={@member}
        current_user_id={@current_scope.user.id}
        can_manage={@is_owner}
        on_remove="remove_member"
        on_role_change="change_role"
        role_options={[{"Admin", "admin"}, {"Member", "member"}, {"Viewer", "viewer"}]}
      />
  """
  attr :member, :map, required: true, doc: "Member struct with :user, :role, and :id"
  attr :current_user_id, :integer, required: true
  attr :can_manage, :boolean, default: false, doc: "Whether current user can manage this member"
  attr :on_remove, :string, default: nil, doc: "Event name for removing member"
  attr :on_role_change, :string, default: nil, doc: "Event name for changing role"
  attr :role_options, :list, default: [], doc: "List of {label, value} tuples for role dropdown"

  def member_row(assigns) do
    display_name = assigns.member.user.display_name || assigns.member.user.email
    show_email = assigns.member.user.display_name != nil
    is_owner = assigns.member.role == "owner"
    is_self = assigns.member.user.id == assigns.current_user_id
    can_remove = assigns.can_manage && !is_owner && !is_self && assigns.on_remove

    can_change_role =
      assigns.can_manage && !is_owner && assigns.on_role_change && assigns.role_options != []

    assigns =
      assigns
      |> assign(:display_name, display_name)
      |> assign(:show_email, show_email)
      |> assign(:is_owner, is_owner)
      |> assign(:can_remove, can_remove)
      |> assign(:can_change_role, can_change_role)

    ~H"""
    <div class="flex items-center justify-between p-3 rounded-lg border border-base-300">
      <div class="flex items-center gap-3">
        <.user_avatar user={@member.user} />
        <div>
          <p class="font-medium">{@display_name}</p>
          <p :if={@show_email} class="text-sm text-base-content/70">
            {@member.user.email}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <%= if @can_change_role do %>
          <form phx-change={@on_role_change} phx-value-member-id={@member.id}>
            <select name="role" class="select select-bordered select-sm w-28">
              <option
                :for={{label, value} <- @role_options}
                value={value}
                selected={@member.role == value}
              >
                {label}
              </option>
            </select>
          </form>
        <% else %>
          <.role_badge role={@member.role} />
        <% end %>
        <.link
          :if={@can_remove}
          phx-click={@on_remove}
          phx-value-id={@member.id}
          class="btn btn-ghost btn-sm text-error"
          data-confirm={gettext("Are you sure you want to remove this member?")}
        >
          <.icon name="x" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Renders a pending invitation row.

  ## Examples

      <.invitation_row invitation={@invitation} on_revoke="revoke_invitation" />
  """
  attr :invitation, :map,
    required: true,
    doc: "Invitation struct with :email, :role, :invited_by, :id"

  attr :on_revoke, :string, default: nil, doc: "Event name for revoking invitation"
  attr :can_revoke, :boolean, default: true, doc: "Whether to show revoke button"

  def invitation_row(assigns) do
    inviter_name =
      assigns.invitation.invited_by.display_name || assigns.invitation.invited_by.email

    assigns = assign(assigns, :inviter_name, inviter_name)

    ~H"""
    <div class="flex items-center justify-between p-3 rounded-lg border border-base-300 bg-base-200/50">
      <div class="flex items-center gap-3">
        <.user_avatar email={@invitation.email} />
        <div>
          <p class="font-medium">{@invitation.email}</p>
          <p class="text-xs text-base-content/50">
            {gettext("Invited by")} {@inviter_name}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <.role_badge role={@invitation.role} />
        <span class="badge badge-ghost badge-sm">{gettext("Pending")}</span>
        <.link
          :if={@can_revoke && @on_revoke}
          phx-click={@on_revoke}
          phx-value-id={@invitation.id}
          class="btn btn-ghost btn-sm text-error"
          data-confirm={gettext("Are you sure you want to revoke this invitation?")}
        >
          <.icon name="x" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end
end
