defmodule Foyer.ProfileScenarios do
  @moduledoc """
  Scenario modules for `Foyer.ProfilePort`. Wired via `Mox.stub_with/2` in
  isolated LiveView tests. Each module describes one variation of the world.

  Convention: names describe the *situation* (Empty, LineStaff, Manager,
  OffShift), not the data shape.
  """

  alias Foyer.Accounts.User
  alias Foyer.Profile.Card
  alias Foyer.Profile.RewardItem
  alias Foyer.Recognitions.Recognition

  # ---------------------------------------------------------------------------
  # Helpers — shared user and recognition builders
  # ---------------------------------------------------------------------------

  @spec user_maya() :: User.t()
  def user_maya do
    %User{
      id: 1,
      name: "Maya Okafor",
      initials: "MO",
      role: :staff,
      department: "Housekeeping",
      title: "Senior Housekeeper · Floor 4",
      languages: ~w(EN FR YO),
      points_balance: 245,
      inserted_at: ~U[2023-03-15 09:00:00Z],
      updated_at: ~U[2023-03-15 09:00:00Z]
    }
  end

  @spec user_charlotte() :: User.t()
  def user_charlotte do
    %User{
      id: 2,
      name: "Charlotte Voss",
      initials: "CV",
      role: :manager,
      department: "Housekeeping",
      title: "Dir. of Housekeeping",
      languages: ~w(EN FR),
      points_balance: 0,
      inserted_at: ~U[2022-01-10 09:00:00Z],
      updated_at: ~U[2022-01-10 09:00:00Z]
    }
  end

  @spec user_sender() :: User.t()
  def user_sender do
    %User{
      id: 3,
      name: "Rafael Mendes",
      initials: "RM",
      role: :manager,
      department: "Front Office",
      title: "Night Manager",
      languages: ~w(EN PT ES),
      points_balance: 0,
      inserted_at: ~U[2022-06-01 09:00:00Z],
      updated_at: ~U[2022-06-01 09:00:00Z]
    }
  end

  @spec recognition_public() :: Recognition.t()
  def recognition_public do
    %Recognition{
      id: 101,
      sender_id: 3,
      recipient_id: 1,
      sender: user_sender(),
      recipient: user_maya(),
      body:
        "Quietly handled a 02:14 guest issue with grace — Mrs. Achebe in 206 called the next morning to praise her by name.",
      values: ["care", "discretion"],
      bonus_points: 0,
      public: true,
      inserted_at: ~U[2026-05-20 10:00:00Z]
    }
  end

  @spec recognition_private() :: Recognition.t()
  def recognition_private do
    %Recognition{
      id: 102,
      sender_id: 3,
      recipient_id: 1,
      sender: user_sender(),
      recipient: user_maya(),
      body: "Private: handled a sensitive situation with extraordinary discretion.",
      values: ["discretion"],
      bonus_points: 25,
      public: false,
      inserted_at: ~U[2026-05-22 14:00:00Z]
    }
  end

  @spec recognition_given() :: Recognition.t()
  def recognition_given do
    %Recognition{
      id: 103,
      sender_id: 1,
      recipient_id: 3,
      sender: user_maya(),
      recipient: user_sender(),
      body: "Rafael stayed calm under pressure during the fire alarm — brilliant.",
      values: ["initiative", "craft"],
      bonus_points: 0,
      public: true,
      inserted_at: ~U[2026-05-18 08:00:00Z]
    }
  end

  @spec sample_rewards() :: [RewardItem.t()]
  def sample_rewards do
    [
      %RewardItem{
        icon: "hero-sparkles",
        title: "Staff meal at the Cellar Chef's tasting",
        description: "Any Tuesday",
        cost: 75
      },
      %RewardItem{
        icon: "hero-gift",
        title: "Donate to the staff fund",
        description: "Supports colleagues in need",
        cost: 100
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Scenario: Empty — user with no recognitions, 0 points
  # ---------------------------------------------------------------------------

  defmodule Empty do
    @moduledoc "A profile with no recognitions and zero points balance."
    @behaviour Foyer.ProfilePort

    @impl true
    def profile_for(subject, _viewer) do
      %Card{
        user: subject,
        received: [],
        given: [],
        points: 0,
        on_shift?: false,
        received_this_month: 0,
        points_earned: []
      }
    end

    @impl true
    def own_profile_for(user) do
      %Card{
        user: user,
        received: [],
        given: [],
        points: 0,
        on_shift?: false,
        received_this_month: 0,
        points_earned: []
      }
    end

    @impl true
    def rewards_catalog, do: []
  end

  # ---------------------------------------------------------------------------
  # Scenario: LineStaff — Maya: on shift, 2 received (1 public, 1 private),
  # 1 given, 245 pts. Matches F.Profile.1-7, F.Profile.9, F.Profile.11.
  # ---------------------------------------------------------------------------

  defmodule LineStaff do
    @moduledoc "Maya Okafor — on shift, mix of public and private recognitions."
    @behaviour Foyer.ProfilePort

    alias Foyer.ProfileScenarios

    @impl true
    def profile_for(subject, viewer) do
      card = own_profile_for(subject)

      if subject.id == viewer.id do
        card
      else
        # Context boundary: strip private, clear given.
        %{card | received: Enum.filter(card.received, & &1.public), given: []}
      end
    end

    @impl true
    def own_profile_for(_user) do
      %Card{
        user: ProfileScenarios.user_maya(),
        received: [
          ProfileScenarios.recognition_private(),
          ProfileScenarios.recognition_public()
        ],
        given: [ProfileScenarios.recognition_given()],
        points: 245,
        on_shift?: true,
        received_this_month: 2,
        points_earned: [ProfileScenarios.recognition_private()]
      }
    end

    @impl true
    def rewards_catalog, do: ProfileScenarios.sample_rewards()
  end

  # ---------------------------------------------------------------------------
  # Scenario: Manager — Charlotte: on shift, 0 received, 2 given, 0 pts.
  # ---------------------------------------------------------------------------

  defmodule Manager do
    @moduledoc "Charlotte Voss — manager, on shift, with given recognitions."
    @behaviour Foyer.ProfilePort

    alias Foyer.ProfileScenarios

    @impl true
    def profile_for(subject, viewer) do
      card = own_profile_for(subject)

      if subject.id == viewer.id do
        card
      else
        %{card | received: Enum.filter(card.received, & &1.public), given: []}
      end
    end

    @impl true
    def own_profile_for(_user) do
      %Card{
        user: ProfileScenarios.user_charlotte(),
        received: [],
        given: [
          ProfileScenarios.recognition_public(),
          ProfileScenarios.recognition_given()
        ],
        points: 0,
        on_shift?: true,
        received_this_month: 0,
        points_earned: []
      }
    end

    @impl true
    def rewards_catalog, do: ProfileScenarios.sample_rewards()
  end

  # ---------------------------------------------------------------------------
  # Scenario: OffShift — on_shift?: false (F.Profile.3, F.Profile.18)
  # ---------------------------------------------------------------------------

  defmodule OffShift do
    @moduledoc "A staff member who is currently off shift."
    @behaviour Foyer.ProfilePort

    alias Foyer.ProfileScenarios

    @impl true
    def profile_for(subject, _viewer) do
      %Card{
        user: subject,
        received: [],
        given: [],
        points: 0,
        on_shift?: false,
        received_this_month: 0,
        points_earned: []
      }
    end

    @impl true
    def own_profile_for(_user) do
      %Card{
        user: ProfileScenarios.user_maya(),
        received: [],
        given: [],
        points: 0,
        on_shift?: false,
        received_this_month: 0,
        points_earned: []
      }
    end

    @impl true
    def rewards_catalog, do: []
  end
end
