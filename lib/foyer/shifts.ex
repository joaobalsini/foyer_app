defmodule Foyer.Shifts do
  @moduledoc """
  Shift lifecycle context. `start_shift/1` and `end_shift/2` are fully
  implemented in the scaffold (the smoke test exercises both). The DB enforces
  "at most one open shift per user" via the
  `shifts_one_open_shift_per_user` partial unique index.
  """
  @behaviour Foyer.ShiftsPort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Repo
  alias Foyer.Shifts.Shift

  @impl true
  @spec current_shift_for(User.t()) :: Shift.t() | nil
  def current_shift_for(%User{id: user_id}) do
    from(s in Shift,
      where: s.user_id == ^user_id and is_nil(s.ended_at),
      order_by: [desc: s.started_at],
      limit: 1,
      preload: [:handoff_channel]
    )
    |> Repo.one()
  end

  @impl true
  @spec last_handoff_for(User.t()) :: Shift.t() | nil
  def last_handoff_for(%User{id: user_id}) do
    cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)

    from(s in Shift,
      join: m in Foyer.Channels.Membership,
      on: m.channel_id == s.handoff_channel_id and m.user_id == ^user_id,
      where:
        not is_nil(s.ended_at) and
          s.ended_at >= ^cutoff and
          s.user_id != ^user_id and
          not is_nil(s.handoff_note),
      order_by: [desc: s.ended_at],
      limit: 1,
      preload: [:user, :handoff_channel]
    )
    |> Repo.one()
  end

  @impl true
  @spec users_on_shift_ids() :: MapSet.t()
  def users_on_shift_ids do
    from(s in Shift, where: is_nil(s.ended_at), select: s.user_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @impl true
  @spec start_shift(User.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def start_shift(%User{id: user_id}) do
    %Shift{}
    |> Shift.changeset(%{user_id: user_id, started_at: DateTime.utc_now()})
    |> Repo.insert()
  end

  @impl true
  @spec end_shift(Shift.t(), map()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def end_shift(%Shift{} = shift, attrs) do
    attrs = Map.put_new_lazy(attrs, "ended_at", fn -> DateTime.utc_now() end)

    shift
    |> Shift.changeset(attrs)
    |> Repo.update()
  end

  # Owned by feature/shifts; this branch carries a local copy until that branch lands on main.
  @impl true
  @spec last_ended_shift_for(User.t()) :: Shift.t() | nil
  def last_ended_shift_for(%User{id: user_id}) do
    from(s in Shift,
      where: s.user_id == ^user_id and not is_nil(s.ended_at),
      order_by: [desc: s.ended_at],
      limit: 1
    )
    |> Repo.one()
  end
end
