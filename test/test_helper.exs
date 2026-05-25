ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Foyer.Repo, :manual)

# Mox mocks — one per port behaviour. config/test.exs points LiveDeps at THESE
# mocks; tests use Mox.stub_with/2 to bind a real context or a scenario module
# per scope. Tests MUST NOT mutate :foyer, :*_context with
# Application.put_env/3 (forbidden by docs/TESTING_GUIDE.md).
Mox.defmock(Foyer.AccountsMock, for: Foyer.AccountsPort)
Mox.defmock(Foyer.ShiftsMock, for: Foyer.ShiftsPort)
Mox.defmock(Foyer.ChannelsMock, for: Foyer.ChannelsPort)
Mox.defmock(Foyer.HouseMock, for: Foyer.HousePort)
Mox.defmock(Foyer.RecognitionsMock, for: Foyer.RecognitionsPort)
Mox.defmock(Foyer.ChatMock, for: Foyer.ChatPort)
Mox.defmock(Foyer.ProfileMock, for: Foyer.ProfilePort)
Mox.defmock(Foyer.TodayMock, for: Foyer.TodayPort)

# Scenario placeholder folders are NOT created yet — they will be added by
# feature-group plans as the first isolated test for that group is written.
# Folder convention (per docs/TESTING_GUIDE.md):
#
#   test/support/scenarios/<port>/empty.ex
#   test/support/scenarios/<port>/busy.ex
#   ...
#
# Each scenario module implements the corresponding port behaviour and is
# wired via `Mox.stub_with(Foyer.XMock, MyScenario)`.
