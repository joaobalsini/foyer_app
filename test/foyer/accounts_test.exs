defmodule Foyer.AccountsTest do
  use Foyer.DataCase, async: true

  import FoyerWeb.ScaffoldFixtures

  alias Foyer.Accounts

  setup do
    {:ok, seed_scaffold!()}
  end

  describe "get_user/1" do
    test "returns nil for malformed string ids" do
      assert Accounts.get_user("not-an-id") == nil
    end

    test "returns nil for missing ids and a user for existing ids", ctx do
      assert Accounts.get_user(-1) == nil
      assert Accounts.get_user(Integer.to_string(ctx.maya.id)).id == ctx.maya.id
    end

    test "raises for values outside the id contract" do
      assert_raise FunctionClauseError, fn -> Accounts.get_user(nil) end
    end
  end
end
