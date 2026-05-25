defmodule Foyer.RecognitionsPort do
  @moduledoc """
  Behaviour for `Foyer.Recognitions`. `give/2` is stubbed until the
  Recognitions feature group lands.
  """

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  @callback feed_public(opts :: keyword()) :: [Recognition.t()]
  @callback received_by(target :: User.t(), viewer :: User.t()) :: [Recognition.t()]
  @callback given_by(target :: User.t(), viewer :: User.t()) :: [Recognition.t()]
  @callback get_recognition!(integer() | String.t(), User.t()) :: Recognition.t()
  @callback compose_changeset(map()) :: Ecto.Changeset.t()
  @callback change_recognition(Recognition.t(), map()) :: Ecto.Changeset.t()
  @callback give(User.t(), map()) ::
              {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback update_recognition(Recognition.t(), User.t(), map()) ::
              {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback remove_recognition(Recognition.t(), User.t()) ::
              {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}
  @callback within_grace_window?(Recognition.t()) :: boolean()
end
