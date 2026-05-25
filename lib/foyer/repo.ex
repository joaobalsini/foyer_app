defmodule Foyer.Repo do
  use Ecto.Repo,
    otp_app: :foyer,
    adapter: Ecto.Adapters.Postgres
end
