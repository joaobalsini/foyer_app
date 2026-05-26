ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Foyer.Repo, :manual)

# Mox mocks — one per context behavior. config/test.exs points LiveDeps at THESE
# mocks; tests use Mox.stub_with/2 to bind a real context or a scenario module
# per scope. Tests MUST NOT mutate :foyer, :*_context with
# Application.put_env/3 (forbidden by docs/TESTING_GUIDE.md).
Mox.defmock(Foyer.AccountsMock, for: Foyer.Accounts.Behavior)
Mox.defmock(Foyer.ShiftsMock, for: Foyer.Shifts.Behavior)
Mox.defmock(Foyer.ChannelsMock, for: Foyer.Channels.Behavior)
Mox.defmock(Foyer.HouseMock, for: Foyer.House.Behavior)
Mox.defmock(Foyer.RecognitionsMock, for: Foyer.Recognitions.Behavior)
Mox.defmock(Foyer.ChatMock, for: Foyer.Chat.Behavior)
Mox.defmock(Foyer.ProfileMock, for: Foyer.Profile.Behavior)
Mox.defmock(Foyer.TodayMock, for: Foyer.Today.Behavior)

# Scenario placeholder folders are NOT created yet — they will be added by
# feature-group plans as the first isolated test for that group is written.
# Folder convention (per docs/TESTING_GUIDE.md):
#
#   test/support/scenarios/<context>/empty.ex
#   test/support/scenarios/<context>/busy.ex
#   ...
#
# Each scenario module implements the corresponding context behavior and is
# wired via `Mox.stub_with(Foyer.XMock, MyScenario)`.
