defmodule Foyer.RecognitionsScenarios.Empty do
  @moduledoc """
  Empty Recognitions world for isolated LiveView tests.

  Every read returns `[]`. Writes / show / edit raise `Ecto.NoResultsError` —
  the LiveView treats that as "not available to you" and pushes back to
  `/house`. Use this scenario when the test renders the `:new` form or any
  state that doesn't depend on existing recognitions.
  """
  @behaviour Foyer.Recognitions.Behavior

  alias Foyer.Recognitions.Recognition

  @impl true
  def feed_public(_opts \\ []), do: []

  @impl true
  def received_by(_target, _viewer), do: []

  @impl true
  def given_by(_target, _viewer), do: []

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
end
