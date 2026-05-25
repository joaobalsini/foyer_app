defmodule FoyerWeb.ScaffoldFixtures do
  @moduledoc """
  Sandbox-owned fixtures for the scaffold smoke test. Inserts a trimmed-down
  version of `priv/repo/seeds.exs` — just what the smoke test asserts against
  — so the test stays fast and async-safe.

  The full seeds (priv/repo/seeds.exs) are still authoritative for manual
  demo runs.
  """

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.Channels.Membership
  alias Foyer.Chat.Conversation
  alias Foyer.Chat.Message
  alias Foyer.Chat.Participant
  alias Foyer.House.Announcement
  alias Foyer.House.AnnouncementAck
  alias Foyer.House.AnnouncementRead
  alias Foyer.Recognitions.Recognition
  alias Foyer.Repo
  alias Foyer.Shifts.Shift

  @spec seed_scaffold!() :: map()
  def seed_scaffold! do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # --- Users ---
    user_specs = [
      {"Maya Okafor", "MO", :staff, "Housekeeping", "Senior Housekeeper · Floor 4", ~w(EN FR YO),
       245},
      {"Charlotte Voss", "CV", :manager, "Housekeeping", "Dir. of Housekeeping", ~w(EN FR), 0},
      {"Rafael Mendes", "RM", :manager, "Front Office", "Night Manager", ~w(EN PT ES), 0},
      {"Aisha Bello", "AB", :staff, "Housekeeping", "Housekeeper · Fl. 4", ~w(EN YO), 60},
      {"Hugo Brandt", "HB", :staff, "Engineering", "Engineering", ~w(EN DE), 100},
      {"Leila Haddad", "LH", :staff, "Front Office", "Front Office", ~w(EN AR FR), 25},
      {"Sebastien Roy", "SR", :manager, "F&B", "Executive Chef", ~w(EN FR), 0},
      {"Jamal Mensah", "JM", :staff, "Housekeeping", "Housekeeper · Fl. 2", ~w(EN TL), 0}
    ]

    users =
      for {name, initials, role, department, title, languages, points} <- user_specs, into: %{} do
        {:ok, u} =
          %User{}
          |> User.changeset(%{
            name: name,
            initials: initials,
            role: role,
            department: department,
            title: title,
            languages: languages,
            points_balance: points
          })
          |> Repo.insert()

        {name, u}
      end

    # --- Channels + memberships ---
    channel_specs = [
      {"housekeeping-floor-4", "Housekeeping · Floor 4", :department,
       ["Maya Okafor", "Aisha Bello", "Hugo Brandt", "Charlotte Voss"]},
      {"all-housekeeping", "All Housekeeping", :department,
       ["Maya Okafor", "Aisha Bello", "Charlotte Voss", "Jamal Mensah"]},
      {"leadership", "Leadership", :department,
       ["Charlotte Voss", "Rafael Mendes", "Sebastien Roy"]},
      {"linden-all", "Linden · All staff", :general, Map.keys(users)}
    ]

    channels =
      for {slug, name, kind, member_names} <- channel_specs, into: %{} do
        {:ok, c} =
          %Channel{}
          |> Channel.changeset(%{slug: slug, name: name, kind: kind})
          |> Repo.insert()

        for member_name <- member_names do
          user = Map.fetch!(users, member_name)

          {:ok, _} =
            %Membership{}
            |> Membership.changeset(%{user_id: user.id, channel_id: c.id})
            |> Repo.insert()
        end

        {slug, c}
      end

    maya = Map.fetch!(users, "Maya Okafor")
    charlotte = Map.fetch!(users, "Charlotte Voss")
    rafael = Map.fetch!(users, "Rafael Mendes")
    aisha = Map.fetch!(users, "Aisha Bello")
    hugo = Map.fetch!(users, "Hugo Brandt")
    jamal = Map.fetch!(users, "Jamal Mensah")
    floor_4 = Map.fetch!(channels, "housekeeping-floor-4")
    all_housekeeping = Map.fetch!(channels, "all-housekeeping")
    leadership = Map.fetch!(channels, "leadership")

    # --- Shifts ---
    six_am = %{now | hour: 6, minute: 0, second: 0}
    seven_thirty = %{now | hour: 7, minute: 30, second: 0}
    night_start = DateTime.add(six_am, -12 * 3600, :second)
    night_end = DateTime.add(now, -2 * 3600, :second)
    yesterday_end = DateTime.add(now, -28 * 3600, :second)

    # On-shift: Maya, Charlotte, Aisha, Hugo.
    for user <- [maya, aisha, hugo] do
      {:ok, _} =
        %Shift{}
        |> Shift.changeset(%{user_id: user.id, started_at: six_am})
        |> Repo.insert()
    end

    {:ok, _} =
      %Shift{}
      |> Shift.changeset(%{user_id: charlotte.id, started_at: seven_thirty})
      |> Repo.insert()

    # Rafael — handoff (ended ~2h ago).
    {:ok, _rafael_shift} =
      %Shift{}
      |> Shift.changeset(%{
        user_id: rafael.id,
        started_at: night_start,
        ended_at: night_end,
        handoff_note: "Rafael · 06:08 — quiet night, 206 settled.",
        handoff_channel_id: floor_4.id
      })
      |> Repo.insert()

    # Jamal — off shift (ended yesterday).
    {:ok, _} =
      %Shift{}
      |> Shift.changeset(%{
        user_id: jamal.id,
        started_at: DateTime.add(yesterday_end, -8 * 3600, :second),
        ended_at: yesterday_end
      })
      |> Repo.insert()

    # --- Announcements ---
    seven_42 = %{now | hour: 7, minute: 42, second: 0}

    {:ok, suite_412} =
      %Announcement{}
      |> Announcement.changeset(%{
        author_id: charlotte.id,
        channel_id: all_housekeeping.id,
        title: "Suite 412 - Allergy protocol in effect",
        body:
          "Guest in 412 has severe tree-nut allergy. Use the marked cleaning kit and check the laminated card on the door before entering.",
        pinned_at: seven_42,
        requires_ack: true,
        published_at: seven_42
      })
      |> Repo.insert()

    {:ok, leadership_only_announcement} =
      %Announcement{}
      |> Announcement.changeset(%{
        author_id: charlotte.id,
        channel_id: leadership.id,
        title: "Leadership only - quarterly review notes",
        body: "Internal — not for staff distribution.",
        requires_ack: false,
        published_at: now
      })
      |> Repo.insert()

    # Pre-existing acks/reads.
    for user <- [aisha, hugo] do
      {:ok, _} =
        %AnnouncementAck{}
        |> AnnouncementAck.changeset(%{
          announcement_id: suite_412.id,
          user_id: user.id,
          ack_at: now
        })
        |> Repo.insert()
    end

    for user <- [aisha, hugo, rafael] do
      {:ok, _} =
        %AnnouncementRead{}
        |> AnnouncementRead.changeset(%{
          announcement_id: suite_412.id,
          user_id: user.id,
          read_at: now
        })
        |> Repo.insert()
    end

    # --- Recognitions ---
    {:ok, maya_recognition} =
      %Recognition{}
      |> Recognition.changeset(%{
        sender_id: rafael.id,
        recipient_id: maya.id,
        body:
          "Quietly handled a 02:14 guest issue with grace — Mrs. Achebe in 206 called the next morning to praise her by name.",
        values: ["care", "discretion"],
        public: true
      })
      |> Repo.insert()

    # A second recognition whose author is on shift (Charlotte) — used by the
    # edit smoke test, which would otherwise hit the off-shift gate.
    {:ok, hugo_recognition} =
      %Recognition{}
      |> Recognition.changeset(%{
        sender_id: charlotte.id,
        recipient_id: hugo.id,
        body:
          "Stayed past 23:00 fixing the Garden Suite shower so we could honour an early check-in.",
        values: ["initiative", "craft"],
        public: true
      })
      |> Repo.insert()

    # --- Conversations + messages ---
    direct_key_mc = Conversation.direct_key([maya.id, charlotte.id])
    eight_14 = %{now | hour: 8, minute: 14, second: 0}

    {:ok, maya_charlotte} =
      %Conversation{}
      |> Conversation.changeset(%{
        kind: :direct,
        direct_key: direct_key_mc,
        last_message_at: eight_14,
        participant_user_ids: [maya.id, charlotte.id]
      })
      |> Repo.insert()

    for user_id <- [maya.id, charlotte.id] do
      {:ok, _} =
        %Participant{}
        |> Participant.changeset(%{conversation_id: maya_charlotte.id, user_id: user_id})
        |> Repo.insert()
    end

    {:ok, _} =
      %Message{}
      |> Message.changeset(%{
        conversation_id: maya_charlotte.id,
        author_id: charlotte.id,
        body: "Morning Maya - guest in 412 needs the laminated card on the door."
      })
      |> Repo.insert()

    {:ok, _} =
      %Message{}
      |> Message.changeset(%{
        conversation_id: maya_charlotte.id,
        author_id: maya.id,
        body: "Confirmed in 412."
      })
      |> Repo.insert()

    # Floor 4 channel conversation.
    {:ok, _conv_floor_4} =
      %Conversation{}
      |> Conversation.changeset(%{
        kind: :channel,
        channel_id: floor_4.id,
        last_message_at: %{now | hour: 8, minute: 2, second: 0}
      })
      |> Repo.insert()

    %{
      maya: maya,
      charlotte: charlotte,
      rafael: rafael,
      aisha: aisha,
      hugo: hugo,
      jamal: jamal,
      suite_412: suite_412,
      leadership_only_announcement: leadership_only_announcement,
      maya_charlotte: maya_charlotte,
      maya_recognition: maya_recognition,
      hugo_recognition: hugo_recognition
    }
  end
end
