defmodule Foyer.Channels.MembershipTest do
  use ExUnit.Case, async: true

  alias Foyer.Channels.Membership

  describe "F.Channels.5 — required fields" do
    test "valid changeset with both fields" do
      cs = Membership.changeset(%Membership{}, %{user_id: 1, channel_id: 2})
      assert cs.valid?
    end

    test "missing user_id produces can't be blank error" do
      cs = Membership.changeset(%Membership{}, %{channel_id: 2})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:user_id]
    end

    test "missing channel_id produces can't be blank error" do
      cs = Membership.changeset(%Membership{}, %{user_id: 1})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:channel_id]
    end

    test "both missing produces errors for each" do
      cs = Membership.changeset(%Membership{}, %{})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:user_id]
      assert {"can't be blank", _} = cs.errors[:channel_id]
    end
  end
end
