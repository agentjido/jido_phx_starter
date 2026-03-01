# Jido PHX Starter

A beginner-friendly starter app for learning **Jido** and **Jido.AI** in a real Phoenix project.

This repo gives you working examples of:

- basic agent actions and signals
- directives (`Schedule`, `Emit`)
- AI chat with tool calling
- Ash + AshJido tool integration
- multi-agent orchestration

If you are new to Elixir, this README is written for you.

## What You Need

Install these first (using the official guides):

- Elixir + Erlang/OTP: [https://elixir-lang.org/install.html](https://elixir-lang.org/install.html)
- PostgreSQL: [https://www.postgresql.org/download/](https://www.postgresql.org/download/)
- Phoenix install checklist: [https://hexdocs.pm/phoenix/installation.html](https://hexdocs.pm/phoenix/installation.html)
- Git: [https://git-scm.com/downloads](https://git-scm.com/downloads)

Quick verify after install:

```bash
elixir --version
mix --version
psql --version
git --version
```

You do **not** need Node.js for this project. Phoenix downloads frontend tooling automatically.

## 1) Set Up Postgres User (One Time)

This app expects:

- username: `postgres`
- password: `postgres`
- host: `localhost`

If your local Postgres user already works with that password, skip this.

Otherwise, run:

```bash
psql -U postgres -d postgres -c "ALTER USER postgres WITH PASSWORD 'postgres';"
```

If that command fails because your local setup is different, update values in:

- `config/dev.exs`
- `config/test.exs`

## 2) Clone + Install + Prepare DB

```bash
git clone https://github.com/agentjido/jido_phx_starter.git
cd jido_phx_starter
mix setup
mix ecto.setup
```

What these commands do:

- `mix setup`: installs dependencies and frontend assets
- `mix ecto.setup`: creates and migrates your local database

## 3) Run the App

```bash
mix phx.server
```

Then open:

- [http://localhost:4000](http://localhost:4000)

You should see the demo index page.

## 4) Try the Demos

Main index:

- [http://localhost:4000](http://localhost:4000)

Direct routes:

- [http://localhost:4000/jido/counter](http://localhost:4000/jido/counter)
- [http://localhost:4000/jido/demand-tracker](http://localhost:4000/jido/demand-tracker)
- [http://localhost:4000/jido/chat](http://localhost:4000/jido/chat)
- [http://localhost:4000/jido/listings](http://localhost:4000/jido/listings)
- [http://localhost:4000/jido/weekend-sale](http://localhost:4000/jido/weekend-sale)

## AI Demos (Optional but Recommended)

`/jido/chat` and `/jido/listings` use `Jido.AI` and require an LLM API key.

At minimum, set:

```bash
export ANTHROPIC_API_KEY="your_key_here"
```

Then restart the server:

```bash
mix phx.server
```

Without a key, AI input controls may stay disabled.

## Run Tests

```bash
mix test
```

## Common Problems

### `connection refused` / DB errors on startup

Your Postgres service is not running, or username/password do not match `config/dev.exs`.

### `mix: command not found`

Elixir is not installed correctly or your shell PATH is not updated.

### Page loads but styling is missing

Stop server and restart:

```bash
mix phx.server
```

Tailwind/esbuild are managed automatically by Phoenix watchers in dev mode.

## Elixir/Phoenix Terms (Quick)

- **Mix**: Elixir's command tool (like `npm` + `make`)
- **Phoenix**: web framework
- **LiveView**: real-time server-rendered UI (no SPA setup needed)
- **Ecto**: database layer

## Next Steps

1. Open `lib/jido_phx_starter_web/demo_metadata.ex` to see how demos are registered.
2. Open `lib/jido_phx_starter/demos/` to inspect each agent/action.
3. Duplicate one demo and build your own variant.

## Helpful Links

- [Jido on Hex](https://hex.pm/packages/jido)
- [Jido.AI on Hex](https://hex.pm/packages/jido_ai)
- [Phoenix Docs](https://hexdocs.pm/phoenix/overview.html)
