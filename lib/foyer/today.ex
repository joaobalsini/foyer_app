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

  @impl true
  @spec brief_for(User.t()) :: Briefing.t()
  def brief_for(%User{} = user) do
    shift = Shifts.current_shift_for(user)
    on_shift? = not is_nil(shift)

    needs_ack = if on_shift?, do: House.needs_ack_from(user), else: []
    handoff = if on_shift?, do: Shifts.last_handoff_for(user), else: nil

    recent_recognitions =
      if on_shift? do
        Recognitions.received_by(user, user) |> Enum.take(3)
      else
        []
      end

    own_announcements =
      if on_shift? and manager?(user),
        do: House.authored_by(user),
        else: []

    last_shift_ended_at =
      case Shifts.last_ended_shift_for(user) do
        nil -> nil
        s -> s.ended_at
      end

    {w_ann, w_msg, w_rec} =
      if on_shift?,
        do: {0, 0, 0},
        else: waiting_counts(user, last_shift_ended_at)

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

  @spec waiting_counts(User.t(), DateTime.t() | nil) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp waiting_counts(user, since) do
    ann = House.unacked_since(user, since)
    msg = Chat.unread_since(user, since)
    rec = Recognitions.private_received_since(user, since)
    {ann, msg, rec}
  end

  @spec manager?(User.t()) :: boolean()
  defp manager?(%User{role: :manager}), do: true
  defp manager?(%User{}), do: false
end
