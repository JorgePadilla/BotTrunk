class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_theme

  THEMES = %w[bottrunk-light bottrunk-dark].freeze

  # The theme Stimulus controller stores the choice in a cookie so the first
  # paint already has the right `data-theme` (no flash of the wrong theme).
  def current_theme
    THEMES.include?(cookies[:theme]) ? cookies[:theme] : "bottrunk-light"
  end
end
