RailsIcons.configure do |config|
  config.default_library = "lucide"
  config.default_variant = "outline"

  # Stroke-based, 1.75px, 16px grid — matches the mockups.
  config.libraries.lucide.outline.default.css = "size-4"
  config.libraries.lucide.outline.default.stroke_width = "1.75"
end
