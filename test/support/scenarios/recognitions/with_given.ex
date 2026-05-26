defmodule Foyer.RecognitionsScenarios.WithGiven do
  @moduledoc """
  Recognitions world where the target user has given exactly one public
  recognition. Mirror of `WithReceived` for the `given_by/2` callback.
  """
  @behaviour Foyer.Recognitions.Behavior

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  @recognition %Recognition{
    id: 9002,
    sender_id: 2,
    recipient_id: 3,
    body: "Quietly handled the late check-in.",
    values: ["initiative", "discretion"],
    bonus_points: 0,
    public: true,
    inserted_at: ~U[2026-05-25 06:00:00Z],
    sender: %User{id: 2, name: "Maya Okafor", initials: "MO", role: :staff},
    recipient: %User{id: 3, name: "Aisha Bello", initials: "AB", role: :staff}
  }

  @impl true
  def feed_public(_opts \\ []), do: []

  @impl true
  def received_by(_target, _viewer), do: []

  @impl true
  def given_by(_target, _viewer), do: [@recognition]

  @impl true
  def private_received_since(_user, _since), do: 0

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

  @doc "The fixed sample recognition this scenario returns from given_by/2."
  @spec sample() :: Recognition.t()
  def sample, do: @recognition
end
