defmodule Foyer.Today.Briefing do
  @moduledoc """
  Aggregated morning-briefing read-model. Returned by
  `Foyer.Today.brief_for/1`. Typed DTO (per ARCHITECTURE.md "no bare maps").
  """
  use TypedStruct

  alias Foyer.Accounts.User
  alias Foyer.House.Announcement
  alias Foyer.Recognitions.Recognition
  alias Foyer.Shifts.Shift

  typedstruct enforce: true do
    field :user, User.t()
    field :shift, Shift.t() | nil
    field :on_shift?, boolean()
    field :handoff, Shift.t() | nil
    field :needs_ack, [Announcement.t()]
    field :recent_recognitions, [Recognition.t()]
    field :own_announcements, [Announcement.t()]
    field :waiting_announcements, non_neg_integer()
    field :waiting_messages, non_neg_integer()
    field :waiting_recognitions, non_neg_integer()
    field :last_shift_ended_at, DateTime.t() | nil
  end

  @spec waiting_total(t()) :: non_neg_integer()
  def waiting_total(%__MODULE__{} = b),
    do: b.waiting_announcements + b.waiting_messages + b.waiting_recognitions
end
