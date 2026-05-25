defmodule FoyerWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use FoyerWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint FoyerWeb.Endpoint

      use FoyerWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import FoyerWeb.ConnCase
    end
  end

  setup tags do
    Foyer.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  POC sign-in for tests: puts `current_user_id` in the session so the
  `:fetch_current_user` plug and `on_mount` hooks have something to load.
  """
  @spec sign_in(Plug.Conn.t(), Foyer.Accounts.User.t()) :: Plug.Conn.t()
  def sign_in(conn, %Foyer.Accounts.User{} = user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:current_user_id, user.id)
  end
end
