defmodule FoyerWeb.Scope do
  @moduledoc """
  The per-connection scope. Built once in the on_mount hook and threaded into
  every LiveView template via `@current_scope`. Layouts and the bottom-nav
  read role and on-shift state from this struct.
  """
  use TypedStruct

  alias Foyer.Accounts.User
  alias Foyer.Shifts.Shift

  typedstruct enforce: true do
    field :user, User.t()
    field :on_shift?, boolean()
    field :shift, Shift.t() | nil
    field :role, :manager | :staff
  end

  @spec for_user(User.t(), Shift.t() | nil) :: t()
  def for_user(%User{} = user, shift) do
    %__MODULE__{
      user: user,
      on_shift?: not is_nil(shift),
      shift: shift,
      role: user.role
    }
  end

  @spec manager?(t()) :: boolean()
  def manager?(%__MODULE__{role: :manager}), do: true
  def manager?(%__MODULE__{}), do: false
end
