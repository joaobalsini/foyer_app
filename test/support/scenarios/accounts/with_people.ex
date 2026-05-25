defmodule Foyer.AccountsScenarios.WithPeople.Static do
  @moduledoc false

  alias Foyer.Accounts.User

  @people [
    %User{
      id: 1,
      name: "Charlotte Voss",
      initials: "CV",
      role: :manager,
      department: "Housekeeping",
      title: "Dir. of Housekeeping",
      languages: ["EN"],
      points_balance: 0
    },
    %User{
      id: 2,
      name: "Maya Okafor",
      initials: "MO",
      role: :staff,
      department: "Housekeeping",
      title: "Senior Housekeeper",
      languages: ["EN"],
      points_balance: 245
    },
    %User{
      id: 3,
      name: "Aisha Bello",
      initials: "AB",
      role: :staff,
      department: "Housekeeping",
      title: "Housekeeper",
      languages: ["EN"],
      points_balance: 60
    }
  ]

  @spec people() :: [User.t()]
  def people, do: @people
end

defmodule Foyer.AccountsScenarios.WithPeople do
  @moduledoc """
  Accounts world that returns a small, fixed roster from `list_people/1`. Other
  callbacks raise or return nil — isolated LiveView tests for Recognitions
  never exercise them at mount time.
  """
  @behaviour Foyer.AccountsPort

  alias Foyer.Accounts.User
  alias Foyer.AccountsScenarios.WithPeople.Static

  @impl true
  def list_pickable_users, do: Static.people()

  @impl true
  def list_people(_opts \\ []), do: Static.people()

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
  def get_user(id) when is_integer(id), do: Enum.find(Static.people(), fn p -> p.id == id end)

  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> get_user(int)
      _ -> nil
    end
  end

  def get_user(_), do: nil

  @doc "The fixed sample roster this scenario returns."
  @spec people() :: [User.t()]
  def people, do: Static.people()
end
