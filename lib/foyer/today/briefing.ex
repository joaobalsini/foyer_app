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
    field :recent_recognition, [Recognition.t()]
    field :waiting_count, non_neg_integer()
  end
end
