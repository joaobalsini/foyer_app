defmodule Foyer.Recognitions.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Recognitions`. `give/2` is stubbed until the
  Recognitions feature group lands.
  """

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  @doc """
  Returns public, non-removed recognitions for the shared recognition feed.

  The current implementation ignores `opts`; callers pass `[]`.
  """
  @callback feed_public(opts :: keyword()) :: [Recognition.t()]

  @doc """
  Returns recognitions received by `target` that are visible to `viewer`.
  """
  @callback received_by(target :: User.t(), viewer :: User.t()) :: [Recognition.t()]

  @doc """
  Returns recognitions given by `target` that are visible to `viewer`.
  """
  @callback given_by(target :: User.t(), viewer :: User.t()) :: [Recognition.t()]

  @doc """
  Counts private recognitions received by the user after `since`, or all time
  when `since` is `nil`.
  """
  @callback private_received_since(User.t(), DateTime.t() | nil) :: non_neg_integer()

  @doc """
  Fetches a recognition visible to the viewer.

  Raises when the recognition is missing, removed, or not visible to the
  viewer.
  """
  @callback get_recognition!(integer() | String.t(), User.t()) :: Recognition.t()

  @doc """
  Builds a changeset for composing a recognition.

  Expected attrs may use string or atom keys:

    * `"recipient_id"` / `:recipient_id` - required recipient user id.
    * `"body"` / `:body` - required recognition body.
    * `"values"` / `:values` - required list of house value strings.
    * `"bonus_points"` / `:bonus_points` - optional manager-only tier:
      `0`, `10`, `25`, `50`, or `100`.
    * `"public"` / `:public` - optional boolean or form boolean; defaults to
      public visibility.
  """
  @callback compose_changeset(map()) :: Ecto.Changeset.t()

  @doc """
  Builds a changeset for editing an existing recognition.

  Accepts the same user-editable attrs as `compose_changeset/1`.
  """
  @callback change_recognition(Recognition.t(), map()) :: Ecto.Changeset.t()

  @doc """
  Creates a recognition from the given sender.

  Expected attrs may use string or atom keys:

    * `"recipient_id"` / `:recipient_id` - required recipient user id.
    * `"body"` / `:body` - required recognition body.
    * `"values"` / `:values` - required list of house value strings.
    * `"bonus_points"` / `:bonus_points` - optional manager-only tier:
      `0`, `10`, `25`, `50`, or `100`; staff submissions are normalized to
      `0`.
    * `"public"` / `:public` - optional boolean or form boolean; defaults to
      public visibility.

  The context sets `sender_id`; callers must not provide it as trusted input.
  """
  @callback give(User.t(), map()) ::
              {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Updates a recognition when the editor is authorized and within the edit
  window.

  Accepts the same user-editable attrs as `give/2`.
  """
  @callback update_recognition(Recognition.t(), User.t(), map()) ::
              {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Soft-removes a recognition when the remover is authorized and within the edit
  window.
  """
  @callback remove_recognition(Recognition.t(), User.t()) ::
              {:ok, Recognition.t()} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Returns whether a recognition is still inside the edit/remove grace window.
  """
  @callback within_grace_window?(Recognition.t()) :: boolean()
end
