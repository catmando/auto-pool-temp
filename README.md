# Auto Pool Temp

Texts you when to turn your pool heater up or down, based on the weather forecast.

You set two anchor points (for example, 95°F air → 80°F pool and 35°F air → 102°F pool),
plus how fast your pool heats up and cools down. The app checks the forecast 1–3 times a
day. It works out the setting that keeps the pool on target, starting early when a cold
snap or heat wave is coming, and texts you only when the setting should change. Reply with
your heater's actual setting if it differs from what the app assumed.

- Rails 8.1, SQLite, Solid Queue (recurring jobs), Hotwire
- Weather: [Open-Meteo](https://open-meteo.com) (free, no API key)
- SMS: Twilio (until it's configured, texts are only logged)

## Setup

```sh
bundle install
bin/rails db:prepare
bin/dev          # local web app, http://localhost:3000 (scheduler runs in production only)
```

Twilio: set `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` and `TWILIO_FROM_NUMBER`. Then point the
number's incoming-message webhook at `POST /twilio/sms`.

## Tests

```sh
bundle exec rspec
bin/ci           # lint, security audits, and specs
```

## Algorithms

Recommendation strategies live in `app/models/recommenders/` and are registered in
`Recommenders.registry`. Pick one per pool in Settings. See `CLAUDE.md` for how
`lookahead` works.

## Deploy (Fly.io)

```sh
fly deploy
```

`fly.toml` describes one always-on machine with SQLite on a volume at `/rails/storage`. The only secret is
`RAILS_MASTER_KEY`. After the first deploy, point the bots at it:
`bin/rails "notify:webhooks[https://auto-pool-temp.fly.dev]"`.
