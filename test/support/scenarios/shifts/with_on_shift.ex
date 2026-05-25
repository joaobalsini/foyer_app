defmodule Foyer.ShiftsScenarios.WithOnShift do
  @moduledoc """
  Shifts world where users 1 and 3 are on shift (ids from AccountsScenarios.WithPeople).
  User 2 (Hugo) is NOT on shift.
  """
  @behaviour Foyer.ShiftsPort

  alias Foyer.Shifts.Shift

  # Users 1 and 3 are on shift
  @on_shift_ids MapSet.new([1, 3])

  @impl true
  def current_shift_for(%{id: id}) do
    if MapSet.member?(@on_shift_ids, id) do
      %Shift{
        id: id,
        user_id: id,
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    else
      nil
    end
  end

  @impl true
  def users_on_shift_ids, do: @on_shift_ids

  @impl true
  def last_handoff_for(_user), do: nil

  @impl true
  def last_ended_shift_for(_user), do: nil

  @impl true
  def end_shift(_shift, _attrs), do: {:error, :not_implemented}

  @impl true
  def start_shift(_user), do: {:error, :not_implemented}
end
