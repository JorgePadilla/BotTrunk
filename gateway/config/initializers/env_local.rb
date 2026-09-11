# frozen_string_literal: true

# Loads `gateway/.env.local` (git-ignored) into ENV in development only, so
# local secrets — the agent wallet mnemonic, an SMTP password — live in one
# file instead of a shell prefix that ends up in your history. Anything
# already exported wins, and production never reads this: Render injects the
# real environment.
#
# Format: KEY=value per line, # for comments, optional surrounding quotes.
# No gem, because a Gemfile change means a Gemfile.lock change, and the
# Docker build runs bundler frozen.
if Rails.env.development?
  path = Rails.root.join(".env.local")

  if path.exist?
    path.each_line do |line|
      next if line.strip.empty? || line.strip.start_with?("#")

      key, _, value = line.strip.partition("=")
      next if key.empty?

      ENV[key.strip] ||= value.strip.gsub(/\A["']|["']\z/, "")
    end
  end
end
