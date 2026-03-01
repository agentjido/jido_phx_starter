defmodule JidoPhxStarter.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        JidoPhxStarter.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:jido_phx_starter, :token_signing_secret)
  end
end
