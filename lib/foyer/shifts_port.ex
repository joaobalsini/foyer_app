defmodule Foyer.ShiftsPort do
  @moduledoc """
  Behaviour for `Foyer.Shifts`. See `Foyer.AccountsPort` for the rationale.
  """

  alias Foyer.Accounts.User
  alias Foyer.Shifts.Shift

  @callback current_shift_for(User.t()) :: Shift.t() | nil
  @callback last_handoff_for(User.t()) :: Shift.t() | nil
  @callback users_on_shift_ids() :: MapSet.t()
  @callback start_shift(User.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  @callback end_shift(Shift.t(), attrs :: map()) ::
              {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Returns the most recent shift for the user that has ended_at set
  (ended_at IS NOT NULL), ordered ended_at desc, limit 1.
  Used to anchor waiting counts for the off-shift view.
  Backed by index(:shifts, [:user_id, :ended_at]) (exists from scaffold migrations).
  """
  @callback last_ended_shift_for(User.t()) :: Shift.t() | nil
end
