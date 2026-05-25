# Foyer seeds — idempotent. Wipes and re-inserts the full demo cast.
#
# Run with: `mix run priv/repo/seeds.exs` (or via the `ecto.setup` alias).
#
# This file is for manual demo / `mix phx.server` walkthroughs. The smoke test
# (`test/foyer_web/scaffold_smoke_test.exs`) owns its fixtures via the
# `FoyerWeb.ScaffoldFixtures` module so it stays sandboxed.

import Ecto.Query

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

# 0. Wipe in FK-friendly order.
for schema <- [
      Message,
      Participant,
      Conversation,
      Recognition,
      AnnouncementAck,
      AnnouncementRead,
      Announcement,
      Shift,
      Membership,
      Channel,
      User
    ] do
  Repo.delete_all(schema)
end

now = DateTime.utc_now() |> DateTime.truncate(:second)

# 1. Users.
user_specs = [
  {"Maya Okafor", "MO", :staff, "Housekeeping", "Senior Housekeeper · Floor 4", ~w(EN FR YO),
   245},
  {"Charlotte Voss", "CV", :manager, "Housekeeping", "Dir. of Housekeeping", ~w(EN FR), 0},
  {"Rafael Mendes", "RM", :manager, "Front Office", "Night Manager", ~w(EN PT ES), 0},
  {"Aisha Bello", "AB", :staff, "Housekeeping", "Housekeeper · Fl. 4", ~w(EN YO), 60},
  {"Tomás Ruiz", "TR", :staff, "Front Office", "Concierge", ~w(EN ES), 30},
  {"Elin Larsen", "EL", :staff, "F&B", "F&B Captain", ~w(EN SV), 0},
  {"Priya Shah", "PS", :staff, "Spa", "Spa Therapist", ~w(EN HI), 0},
  {"Hugo Brandt", "HB", :staff, "Engineering", "Engineering", ~w(EN DE), 100},
  {"Leila Haddad", "LH", :staff, "Front Office", "Front Office", ~w(EN AR FR), 25},
  {"Sebastien Roy", "SR", :manager, "F&B", "Executive Chef", ~w(EN FR), 0},
  {"Jamal Mensah", "JM", :staff, "Housekeeping", "Housekeeper · Fl. 2", ~w(EN TL), 0},
  {"Nina Kohler", "NK", :staff, "Housekeeping", "Housekeeper · Fl. 3", ~w(EN DE), 0},
  {"Olu Sanya", "OS", :staff, "Housekeeping", "Houseman", ~w(EN YO), 0},
  {"Kasia Piotrowska", "KP", :staff, "Housekeeping", "Housekeeper · Fl. 5", ~w(EN PL), 0}
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

# 2. Channels + memberships.
channel_specs = [
  {"housekeeping-floor-4", "Housekeeping · Floor 4", :department,
   ["Maya Okafor", "Aisha Bello", "Hugo Brandt", "Charlotte Voss"]},
  {"all-housekeeping", "All Housekeeping", :department,
   [
     "Maya Okafor",
     "Aisha Bello",
     "Charlotte Voss",
     "Jamal Mensah",
     "Nina Kohler",
     "Olu Sanya",
     "Kasia Piotrowska"
   ]},
  {"f-and-b", "F&B", :department, ["Sebastien Roy", "Elin Larsen"]},
  {"concierge-front-office", "Concierge & Front Office", :department,
   ["Tomás Ruiz", "Leila Haddad"]},
  {"engineering", "Engineering", :department, ["Hugo Brandt"]},
  {"leadership", "Leadership", :department, ["Charlotte Voss", "Rafael Mendes", "Sebastien Roy"]},
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

# 3. Shifts.
six_am = %{now | hour: 6, minute: 0, second: 0}
seven_thirty = %{now | hour: 7, minute: 30, second: 0}
night_start = DateTime.add(six_am, -12 * 3600, :second)
night_end = DateTime.add(now, -2 * 3600, :second)
yesterday_end = DateTime.add(now, -28 * 3600, :second)

for member_name <- [
      "Maya Okafor",
      "Aisha Bello",
      "Hugo Brandt",
      "Tomás Ruiz",
      "Elin Larsen",
      "Priya Shah",
      "Leila Haddad",
      "Sebastien Roy"
    ] do
  user = Map.fetch!(users, member_name)

  {:ok, _} =
    %Shift{}
    |> Shift.changeset(%{user_id: user.id, started_at: six_am})
    |> Repo.insert()
end

charlotte = Map.fetch!(users, "Charlotte Voss")

{:ok, _} =
  %Shift{}
  |> Shift.changeset(%{user_id: charlotte.id, started_at: seven_thirty})
  |> Repo.insert()

rafael = Map.fetch!(users, "Rafael Mendes")
floor_4 = Map.fetch!(channels, "housekeeping-floor-4")

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

for member_name <- ["Jamal Mensah", "Nina Kohler", "Olu Sanya", "Kasia Piotrowska"] do
  user = Map.fetch!(users, member_name)
  yesterday_start = DateTime.add(yesterday_end, -8 * 3600, :second)

  {:ok, _} =
    %Shift{}
    |> Shift.changeset(%{
      user_id: user.id,
      started_at: yesterday_start,
      ended_at: yesterday_end
    })
    |> Repo.insert()
end

# 4. Announcements.
seven_42 = %{now | hour: 7, minute: 42, second: 0}
yesterday = DateTime.add(now, -24 * 3600, :second)
two_days_ago = DateTime.add(now, -2 * 24 * 3600, :second)

all_housekeeping = Map.fetch!(channels, "all-housekeeping")
f_and_b = Map.fetch!(channels, "f-and-b")
concierge = Map.fetch!(channels, "concierge-front-office")
sebastien = Map.fetch!(users, "Sebastien Roy")
tomas = Map.fetch!(users, "Tomás Ruiz")

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

{:ok, _} =
  %Announcement{}
  |> Announcement.changeset(%{
    author_id: sebastien.id,
    channel_id: f_and_b.id,
    title: "Truffle menu launches Thursday",
    body: "Tasting Wednesday 16:00. Wines pre-paired by sommelier.",
    requires_ack: false,
    published_at: yesterday
  })
  |> Repo.insert()

{:ok, _} =
  %Announcement{}
  |> Announcement.changeset(%{
    author_id: tomas.id,
    channel_id: concierge.id,
    title: "Reminder - the new umbrella stand",
    body: "Brass stand by the lobby. Old wicker stand to be retired.",
    requires_ack: false,
    published_at: two_days_ago
  })
  |> Repo.insert()

{:ok, _} =
  %Announcement{}
  |> Announcement.changeset(%{
    author_id: charlotte.id,
    channel_id: all_housekeeping.id,
    title: "New uniform supplier - measurements by Friday",
    body: "Bookings 09:00-18:00 in the staff room. Bring your ID.",
    requires_ack: true,
    published_at: yesterday
  })
  |> Repo.insert()

aisha = Map.fetch!(users, "Aisha Bello")
hugo = Map.fetch!(users, "Hugo Brandt")

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

# 5. Recognitions.
maya = Map.fetch!(users, "Maya Okafor")
leila = Map.fetch!(users, "Leila Haddad")

{:ok, _} =
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

{:ok, _} =
  %Recognition{}
  |> Recognition.changeset(%{
    sender_id: charlotte.id,
    recipient_id: maya.id,
    body:
      "Three months running as Floor 4 lead with the highest \"would stay again\" score in the property. Steady, quiet, exceptional.",
    values: ["craft", "excellence"],
    public: true
  })
  |> Repo.insert()

{:ok, _} =
  %Recognition{}
  |> Recognition.changeset(%{
    sender_id: leila.id,
    recipient_id: hugo.id,
    body:
      "Stayed late to track down the radiator rattle in 304 before the guest arrived. Initiative under pressure.",
    values: ["initiative", "craft"],
    public: true,
    bonus_points: 0
  })
  |> Repo.insert()

# 6. Conversations + messages.
linden_all = Map.fetch!(channels, "linden-all")

direct_key_mc = Conversation.direct_key([maya.id, charlotte.id])
eight_14 = %{now | hour: 8, minute: 14, second: 0}
eight_13 = %{now | hour: 8, minute: 13, second: 0}
eight_12 = %{now | hour: 8, minute: 12, second: 0}
eight_11 = %{now | hour: 8, minute: 11, second: 0}

{:ok, conv_mc} =
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
    |> Participant.changeset(%{conversation_id: conv_mc.id, user_id: user_id})
    |> Repo.insert()
end

for {body, author_id, ts} <- [
      {"Morning Maya - guest in 412 needs the laminated card on the door.", charlotte.id,
       eight_11},
      {"On it.", maya.id, eight_12},
      {"Thank you - the allergy kit is in the trolley already.", charlotte.id, eight_13},
      {"Confirmed in 412.", maya.id, eight_14}
    ] do
  {:ok, _msg} =
    %Message{}
    |> Message.changeset(%{
      conversation_id: conv_mc.id,
      author_id: author_id,
      body: body
    })
    |> Repo.insert()

  from(m in Message,
    where: m.conversation_id == ^conv_mc.id and m.author_id == ^author_id and m.body == ^body
  )
  |> Repo.update_all(set: [inserted_at: ts])
end

{:ok, conv_floor_4} =
  %Conversation{}
  |> Conversation.changeset(%{
    kind: :channel,
    channel_id: floor_4.id,
    last_message_at: %{now | hour: 8, minute: 2, second: 0}
  })
  |> Repo.insert()

for {body, author_name, ts} <- [
      {"Trolley re-stocked, Floor 4 ready.", "Aisha Bello",
       %{now | hour: 7, minute: 55, second: 0}},
      {"Radiator in 304 - fixed.", "Hugo Brandt", %{now | hour: 8, minute: 0, second: 0}},
      {"Allergy kit confirmed in 412.", "Maya Okafor", %{now | hour: 8, minute: 2, second: 0}}
    ] do
  author = Map.fetch!(users, author_name)

  {:ok, _} =
    %Message{}
    |> Message.changeset(%{
      conversation_id: conv_floor_4.id,
      author_id: author.id,
      body: body
    })
    |> Repo.insert()

  from(m in Message,
    where: m.conversation_id == ^conv_floor_4.id and m.author_id == ^author.id and m.body == ^body
  )
  |> Repo.update_all(set: [inserted_at: ts])
end

direct_key_ma = Conversation.direct_key([maya.id, aisha.id])

{:ok, conv_ma} =
  %Conversation{}
  |> Conversation.changeset(%{
    kind: :direct,
    direct_key: direct_key_ma,
    last_message_at: yesterday,
    participant_user_ids: [maya.id, aisha.id]
  })
  |> Repo.insert()

for user_id <- [maya.id, aisha.id] do
  {:ok, _} =
    %Participant{}
    |> Participant.changeset(%{conversation_id: conv_ma.id, user_id: user_id})
    |> Repo.insert()
end

{:ok, _} =
  %Message{}
  |> Message.changeset(%{
    conversation_id: conv_ma.id,
    author_id: aisha.id,
    body: "Swapping with you for the 18:00 wrap?"
  })
  |> Repo.insert()

{:ok, conv_linden} =
  %Conversation{}
  |> Conversation.changeset(%{
    kind: :channel,
    channel_id: linden_all.id,
    last_message_at: yesterday
  })
  |> Repo.insert()

{:ok, _} =
  %Message{}
  |> Message.changeset(%{
    conversation_id: conv_linden.id,
    author_id: charlotte.id,
    body: "Welcome to our newest housekeepers, Kasia and Nina."
  })
  |> Repo.insert()

direct_key_mr = Conversation.direct_key([maya.id, rafael.id])
monday = DateTime.add(now, -3 * 24 * 3600, :second)

{:ok, conv_mr} =
  %Conversation{}
  |> Conversation.changeset(%{
    kind: :direct,
    direct_key: direct_key_mr,
    last_message_at: monday,
    participant_user_ids: [maya.id, rafael.id]
  })
  |> Repo.insert()

for user_id <- [maya.id, rafael.id] do
  {:ok, _} =
    %Participant{}
    |> Participant.changeset(%{conversation_id: conv_mr.id, user_id: user_id})
    |> Repo.insert()
end

{:ok, _} =
  %Message{}
  |> Message.changeset(%{
    conversation_id: conv_mr.id,
    author_id: rafael.id,
    body: "All clear handing over Monday's set - see you in 412."
  })
  |> Repo.insert()

IO.puts(
  "Seeded #{Repo.aggregate(User, :count)} users, " <>
    "#{Repo.aggregate(Channel, :count)} channels, " <>
    "#{Repo.aggregate(Announcement, :count)} announcements, " <>
    "#{Repo.aggregate(Conversation, :count)} conversations, " <>
    "#{Repo.aggregate(Message, :count)} messages."
)
