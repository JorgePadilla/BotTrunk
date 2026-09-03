require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Gateway
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "UTC"
    config.i18n.default_locale = :en
    config.i18n.available_locales = [ :en, :es ]

    # ViewComponent previews double as Lookbook pages and as fixtures for tests.
    config.view_component.previews.paths << Rails.root.join("test/components/previews")
    config.view_component.previews.default_layout = "component_preview"
  end
end
