defmodule Foyer.RecognitionsScenarios.WithReceived do
  @moduledoc """
  Recognitions world where the target user has received exactly one public
  recognition. Used by isolated tests that render a profile card or any
  surface that lists `received_by/2`.

  The recognition is returned regardless of viewer — scenarios describe the
  shape of the world, not the visibility policy. Tests that pin the
  third-party-filter rule should use `Mox.expect/3` inline (see
  TESTING_GUIDE §"When to keep expect/3 instead").
  """
  @behaviour Foyer.RecognitionsPort

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  @recognition %Recognition{
    id: 9001,
    sender_id: 1,
    recipient_id: 2,
    body: "Held the floor together.",
    values: ["care"],
    bonus_points: 0,
    public: true,
    inserted_at: ~U[2026-05-25 06:00:00Z],
    sender: %User{id: 1, name: "Charlotte Voss", initials: "CV", role: :manager},
    recipient: %User{id: 2, name: "Maya Okafor", initials: "MO", role: :staff}
  }

  @impl true
  def feed_public(_opts \\ []), do: []

  @impl true
  def received_by(_target, _viewer), do: [@recognition]

  @impl true
  def given_by(_target, _viewer), do: []

  @impl true
  def get_recognition!(_id, _viewer), do: raise(Ecto.NoResultsError, queryable: Recognition)

  @impl true
  def compose_changeset(attrs \\ %{}), do: Recognition.changeset(%Recognition{}, attrs)

  @impl true
  def change_recognition(%Recognition{} = recognition, attrs \\ %{}),
    do: Recognition.changeset(recognition, attrs)

  @impl true
  def give(_sender, _attrs), do: {:error, :not_implemented}

  @impl true
  def update_recognition(_recognition, _editor, _attrs), do: {:error, :not_implemented}

  @impl true
  def remove_recognition(_recognition, _remover), do: {:error, :not_implemented}

  @impl true
  def within_grace_window?(_recognition), do: false

  @doc "The fixed sample recognition this scenario returns from received_by/2."
  @spec sample() :: Recognition.t()
  def sample, do: @recognition
end
