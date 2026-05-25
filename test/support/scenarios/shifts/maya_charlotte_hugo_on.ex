defmodule Foyer.ShiftsScenarios.MayaCharlotteHugoOn do
  @moduledoc """
  Shifts scenario: Maya, Charlotte, and Hugo are on shift; Jamal is off shift.
  Pins the F.Chat.11 picker tag rendering branch.
  """
  @behaviour Foyer.ShiftsPort

  alias Foyer.ChatScenarios.Fixtures

  @impl true
  def users_on_shift_ids do
    MapSet.new([Fixtures.maya().id, Fixtures.charlotte().id, Fixtures.hugo().id])
  end

  @impl true
  def current_shift_for(%{id: id} = _user) do
    if MapSet.member?(users_on_shift_ids(), id) do
      %Foyer.Shifts.Shift{id: 1000 + id, user_id: id, started_at: ~U[2026-05-25 06:00:00Z]}
    else
      nil
    end
  end

  @impl true
  def last_handoff_for(_user), do: nil

  @impl true
  def start_shift(_user),
    do: {:error, %Ecto.Changeset{action: :insert, valid?: false, data: %Foyer.Shifts.Shift{}}}

  @impl true
  def end_shift(_shift, _attrs),
    do: {:error, %Ecto.Changeset{action: :update, valid?: false, data: %Foyer.Shifts.Shift{}}}
end
