# frozen_string_literal: true

# Loads `gateway/.env.local` (git-ignored) into ENV, in development only, so
# local secrets — the agent wallet mnemonic, an SMTP password — live in one
# file instead of a shell prefix that ends up in your history.
#
# Required from `config/boot.rb`, not from an initializer: initializers run
# *after* `config/environments/development.rb`, which reads ENV to decide
# whether SMTP is configured. Loaded any later and every one of these is
# invisible to that decision.
#
# Anything already exported wins. Production never reads this — Render injects
# the real environment. No gem, because a Gemfile change means a Gemfile.lock
# change and the Docker build runs bundler frozen.
#
# Format: KEY=value per line, # for comments, optional surrounding quotes.
if (ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development") == "development"
  path = File.expand_path("../.env.local", __dir__)

  if File.exist?(path)
    File.foreach(path) do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      key, _, value = line.partition("=")
      key = key.strip
      next if key.empty?

      ENV[key] ||= value.strip.gsub(/\A["']|["']\z/, "")
    end
  end
end
