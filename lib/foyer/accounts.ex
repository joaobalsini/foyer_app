defmodule Foyer.Accounts do
  @moduledoc """
  User-facing accounts context. Read-side only in the scaffold — the POC user
  picker (`/`) calls `list_pickable_users/0`; the on-mount hook calls
  `get_user/1` to build the scope.
  """
  @behaviour Foyer.AccountsPort

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
  def list_people(_opts \\ []) do
    from(u in User,
      order_by: [asc: u.name],
      preload: [memberships: :channel]
    )
    |> Repo.all()
  end

  @spec current_shift_for(User.t()) :: Foyer.Shifts.Shift.t() | nil
  defdelegate current_shift_for(user), to: Shifts
end
