import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/foyer start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :foyer, FoyerWeb.Endpoint, server: true
end

config :foyer, FoyerWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# All environments read DATABASE_URL (or TEST_DATABASE_URL in test).
# No credentials are baked into compile-time config files — the same
# compiled artifact runs in dev, test, staging, and production.
maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

if config_env() == :test do
  database_url =
    System.get_env("TEST_DATABASE_URL") ||
      "ecto://postgres:postgres@localhost:5432/foyer_test"

  config :foyer, Foyer.Repo,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2,
    socket_options: maybe_ipv6
else
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :foyer, Foyer.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6
end

# secret_key_base — runtime config in every env so the same compiled artifact
# runs in dev, test, staging, and prod. Dev/test fall back to a stable
# placeholder; prod refuses to boot without a real value.
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    case config_env() do
      :prod ->
        raise """
        environment variable SECRET_KEY_BASE is missing.
        You can generate one by calling: mix phx.gen.secret
        """

      _ ->
        "dev_secret_key_base_padding_padding_padding_padding_padding_padding_pad"
    end

config :foyer, FoyerWeb.Endpoint, secret_key_base: secret_key_base

if config_env() == :prod do
  host = System.get_env("PHX_HOST") || "example.com"

  config :foyer, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :foyer, FoyerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ]
end
