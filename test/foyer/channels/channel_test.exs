defmodule Foyer.Channels.ChannelTest do
  use ExUnit.Case, async: true

  alias Foyer.Channels.Channel

  describe "F.Channels.2 — required fields" do
    test "valid changeset with all fields" do
      cs =
        Channel.changeset(%Channel{}, %{
          name: "Housekeeping",
          slug: "housekeeping",
          kind: :department
        })

      assert cs.valid?
    end

    test "missing name produces can't be blank error" do
      cs = Channel.changeset(%Channel{}, %{slug: "housekeeping", kind: :department})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:name]
    end

    test "missing slug produces can't be blank error" do
      cs = Channel.changeset(%Channel{}, %{name: "Housekeeping", kind: :department})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:slug]
    end

    test "missing kind produces can't be blank error" do
      cs = Channel.changeset(%Channel{}, %{name: "Housekeeping", slug: "housekeeping"})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:kind]
    end

    test "all three missing produces errors for each" do
      cs = Channel.changeset(%Channel{}, %{})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:name]
      assert {"can't be blank", _} = cs.errors[:slug]
      assert {"can't be blank", _} = cs.errors[:kind]
    end
  end

  describe "F.Channels.3 — kind enum constraint" do
    test "department is valid" do
      cs =
        Channel.changeset(%Channel{}, %{
          name: "Housekeeping",
          slug: "housekeeping",
          kind: :department
        })

      assert cs.valid?
    end

    test "general is valid" do
      cs = Channel.changeset(%Channel{}, %{name: "All staff", slug: "all-staff", kind: :general})
      assert cs.valid?
    end

    test "invalid kind value produces error" do
      cs = Channel.changeset(%Channel{}, %{name: "Test", slug: "test", kind: :invalid})
      refute cs.valid?
      assert cs.errors[:kind] != nil
    end

    test "string kind outside enum produces error" do
      cs = Channel.changeset(%Channel{}, %{name: "Test", slug: "test", kind: "other"})
      refute cs.valid?
      assert cs.errors[:kind] != nil
    end
  end
end
