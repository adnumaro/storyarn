# Storyarn

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Production runtime requirements

Production is fail-fast: the release will not start if required infrastructure
variables are missing. Local file storage and local email adapters are only for
development/test.

Required in production:

- Core: `DATABASE_URL`, `SECRET_KEY_BASE`, `CLOAK_KEY`, `PHX_HOST`
- Email: `RESEND_API_KEY`, `MAILER_FROM_EMAIL`
- Storage: Fly Tigris or another S3-compatible provider with
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `BUCKET_NAME`,
  `AWS_ENDPOINT_URL_S3`; `AWS_PUBLIC_URL` is optional

Optional production variables include `MAILER_FROM_NAME`, `REDIS_URL`,
`DNS_CLUSTER_QUERY`, `SENTRY_DSN`, and PostHog settings. See `.env.example` for
the complete list.

Ready to run in production? Please [check the Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
