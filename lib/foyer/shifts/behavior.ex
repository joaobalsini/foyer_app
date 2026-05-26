defmodule Foyer.Shifts.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Shifts`. See `Foyer.Accounts.Behavior` for the rationale.
  """

  alias Foyer.Accounts.User
  alias Foyer.Shifts.Shift

  @doc """
  Returns the user's currently open shift, or `nil` when the user is off shift.
  """
  @callback current_shift_for(User.t()) :: Shift.t() | nil

  @doc """
  Returns the user's latest handoff shift used by shift status surfaces.
  """
  @callback last_handoff_for(User.t()) :: Shift.t() | nil

  @doc """
  Returns a set of user ids that currently have open shifts.
  """
  @callback users_on_shift_ids() :: MapSet.t()

  @doc """
  Starts a shift for the user.
  """
  @callback start_shift(User.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Ends the given shift with handoff attributes.

  Expected attrs may use string or atom keys:

    * `"handoff_note"` / `:handoff_note` - optional handoff note text.
    * `"handoff_channel_id"` / `:handoff_channel_id` - optional channel id for
      the handoff note.
    * `"ended_at"` / `:ended_at` - optional end timestamp. When omitted, the
      context fills it with the current time.
  """
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
