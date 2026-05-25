{
  description = "Foyer — staff communications platform for luxury hotel groups";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Beam toolchain — Erlang/OTP 28 + Elixir 1.19.
        beam = pkgs.beam.packages.erlang_28;
        erlang = beam.erlang;
        elixir = beam.elixir_1_19;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            elixir
            erlang
            beam.hex
            beam.rebar3
            pkgs.nodejs_22
            pkgs.postgresql_17
            pkgs.git
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.inotify-tools
            pkgs.libnotify
          ];

          shellHook = ''
            # Keep mix / hex / rebar state inside the project so each repo
            # is hermetic and the host home directory is untouched.
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            export REBAR_CACHE_DIR="$PWD/.nix-rebar/cache"
            export REBAR_GLOBAL_CONFIG_DIR="$PWD/.nix-rebar/config"
            export PATH="$MIX_HOME/escripts:$HEX_HOME/bin:$PWD/bin:$PATH"

            # Erlang shell history across REPL sessions.
            export ERL_AFLAGS="-kernel shell_history enabled"

            # Postgres lives entirely inside the project (./.postgres).
            export PGDATA="$PWD/.postgres/data"
            export PGLOG="$PWD/.postgres/postgres.log"
            export PGHOST="localhost"
            export PGPORT="5432"
            export PGUSER="postgres"
          '';
        };
      });
}
