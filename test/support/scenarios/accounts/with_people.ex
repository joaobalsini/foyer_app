defmodule Foyer.AccountsScenarios.WithPeople do
  @moduledoc """
  Accounts world with a fixed roster of three users for isolated LiveView tests.

  User IDs are stable (1, 2, 3) so tests can assert on `#people-row-<id>`.
  The user with id 1 is on-shift; id 2 is off-shift; id 3 is on-shift. Tests
  use the shifts scenario to control on-shift state.
  """
  @behaviour Foyer.Accounts.Behavior

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.Channels.Membership

  @floor_4 %Channel{
    id: 101,
    name: "Housekeeping · Floor 4",
    slug: "housekeeping-floor-4",
    kind: :department
  }
  @all_hk %Channel{id: 102, name: "All Housekeeping", slug: "all-housekeeping", kind: :department}

  @people [
    %User{
      id: 1,
      name: "Maya Okafor",
      initials: "MO",
      role: :staff,
      department: "Housekeeping",
      title: "Senior Housekeeper · Floor 4",
      languages: ["EN"],
      points_balance: 245,
      memberships: [
        %Membership{id: 1, user_id: 1, channel_id: 101, channel: @floor_4},
        %Membership{id: 2, user_id: 1, channel_id: 102, channel: @all_hk}
      ]
    },
    %User{
      id: 2,
      name: "Hugo Brandt",
      initials: "HB",
      role: :staff,
      department: "Engineering",
      title: "Engineering",
      languages: ["EN"],
      points_balance: 100,
      memberships: []
    },
    %User{
      id: 3,
      name: "Aisha Bello",
      initials: "AB",
      role: :staff,
      department: "Housekeeping",
      title: "Housekeeper · Fl. 4",
      languages: ["EN"],
      points_balance: 60,
      memberships: [
        %Membership{id: 3, user_id: 3, channel_id: 101, channel: @floor_4}
      ]
    }
  ]

  @impl true
  def list_pickable_users, do: @people

  @impl true
  def list_people(opts \\ []) do
    case Keyword.get(opts, :channel_id) do
      nil ->
        @people

      channel_id when is_integer(channel_id) ->
        filter_by_channel(@people, channel_id)

      channel_id when is_binary(channel_id) ->
        list_people(channel_id: String.to_integer(channel_id))
    end
  end

  defp filter_by_channel(people, channel_id) do
    Enum.filter(people, fn p ->
      Enum.any?(p.memberships, fn m -> m.channel_id == channel_id end)
    end)
  end

  @impl true
  def get_user!(id) when is_integer(id) do
    case get_user(id) do
      nil -> raise Ecto.NoResultsError, queryable: User
      user -> user
    end
  end

  def get_user!(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> get_user!(int)
      _ -> raise Ecto.NoResultsError, queryable: User
    end
  end

  @impl true
  def get_user(id) when is_integer(id), do: Enum.find(@people, fn p -> p.id == id end)

  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> get_user(int)
      _ -> nil
    end
  end

  def get_user(_), do: nil

  @spec people() :: [User.t()]
  def people, do: @people
end
