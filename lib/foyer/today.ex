defmodule Foyer.Today do
  @moduledoc """
  Read-only morning-briefing orchestrator. Calls cousin contexts (Shifts,
  House, Recognitions, Chat) — see plan §6.8 for the conscious trade-off.
  Today is strictly read-only; all writes flow directly from LiveView to the
  owning context.
  """
  @behaviour Foyer.TodayPort

  alias Foyer.Accounts.User
  alias Foyer.Chat
  alias Foyer.House
  alias Foyer.Recognitions
  alias Foyer.Shifts
  alias Foyer.Today.Briefing

  @type deps :: %{
          shifts: module(),
          house: module(),
          recognitions: module(),
          chat: module()
        }

  @impl true
  @spec brief_for(User.t()) :: Briefing.t()
  def brief_for(%User{} = user) do
    brief_for(user, default_deps())
  end

  @spec brief_for(User.t(), deps()) :: Briefing.t()
  def brief_for(%User{} = user, deps) do
    shift = deps.shifts.current_shift_for(user)
    on_shift? = not is_nil(shift)

    needs_ack = if on_shift?, do: deps.house.needs_ack_from(user), else: []
    handoff = if on_shift?, do: deps.shifts.last_handoff_for(user), else: nil

    recent_recognitions = if on_shift?, do: recent_recognitions(user, deps), else: []

    own_announcements =
      if on_shift? and manager?(user),
        do: deps.house.authored_by(user),
        else: []

    last_shift_ended_at =
      case deps.shifts.last_ended_shift_for(user) do
        nil -> nil
        s -> s.ended_at
      end

    {w_ann, w_msg, w_rec} =
      if on_shift?,
        do: {0, 0, 0},
        else: waiting_counts(user, last_shift_ended_at, deps)

    %Briefing{
      user: user,
      shift: shift,
      on_shift?: on_shift?,
      handoff: handoff,
      needs_ack: needs_ack,
      recent_recognitions: recent_recognitions,
      own_announcements: own_announcements,
      waiting_announcements: w_ann,
      waiting_messages: w_msg,
      waiting_recognitions: w_rec,
      last_shift_ended_at: last_shift_ended_at
    }
  end

  @spec waiting_counts(User.t(), DateTime.t() | nil, deps()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp waiting_counts(user, since, deps) do
    ann = deps.house.unacked_since(user, since)
    msg = deps.chat.unread_since(user, since)
    rec = deps.recognitions.private_received_since(user, since)
    {ann, msg, rec}
  end

  defp recent_recognitions(user, deps) do
    received = deps.recognitions.received_by(user, user)

    own_private =
      deps.recognitions.given_by(user, user)
      |> Enum.reject(& &1.public)

    (received ++ own_private)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&recognition_inserted_at/1, {:desc, DateTime})
    |> Enum.take(3)
  end

  defp recognition_inserted_at(%{inserted_at: %DateTime{} = inserted_at}), do: inserted_at
  defp recognition_inserted_at(_recognition), do: ~U[1970-01-01 00:00:00Z]

  @spec default_deps() :: deps()
  defp default_deps do
    %{
      shifts: Shifts,
      house: House,
      recognitions: Recognitions,
      chat: Chat
    }
  end

  @spec manager?(User.t()) :: boolean()
  defp manager?(%User{role: :manager}), do: true
  defp manager?(%User{}), do: false
end
