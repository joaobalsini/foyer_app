defmodule Foyer.Accounts do
  @moduledoc """
  User-facing accounts context. Read-side only in the scaffold — the POC user
  picker (`/`) calls `list_pickable_users/0`; the on-mount hook calls
  `get_user/1` to build the scope.
  """
  @behaviour Foyer.Accounts.Behavior

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Repo
  alias Foyer.Shifts

  @impl true
  @spec list_pickable_users() :: [User.t()]
  def list_pickable_users do
    User
    |> order_by([u], asc: u.name)
    |> Repo.all()
  end

  @impl true
  @spec get_user!(integer() | String.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @impl true
  @spec get_user(integer() | String.t()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @impl true
  @spec list_people(keyword()) :: [User.t()]
  def list_people(opts \\ []) do
    base =
      from(u in User,
        order_by: [asc: u.name],
        preload: [memberships: :channel]
      )

    base
    |> maybe_filter_by_channel(opts[:channel_id])
    |> Repo.all()
  end

  @spec maybe_filter_by_channel(Ecto.Queryable.t(), String.t() | integer() | nil) ::
          Ecto.Queryable.t()
  defp maybe_filter_by_channel(query, nil), do: query

  defp maybe_filter_by_channel(query, channel_id) when is_binary(channel_id) do
    maybe_filter_by_channel(query, String.to_integer(channel_id))
  end

  defp maybe_filter_by_channel(query, channel_id) when is_integer(channel_id) do
    from(u in query,
      join: m in Foyer.Channels.Membership,
      on: m.user_id == u.id and m.channel_id == ^channel_id
    )
  end

  @spec current_shift_for(User.t()) :: Foyer.Shifts.Shift.t() | nil
  defdelegate current_shift_for(user), to: Shifts
end
