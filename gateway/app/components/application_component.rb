# frozen_string_literal: true

# Base class for every ViewComponent in the app.
#
# Conventions (see CLAUDE.md):
# - One component per reusable piece of UI; styled with daisyUI + Tailwind classes only.
# - Keyword arguments, no positional ones. Booleans end in `?` in readers.
# - Every component has a preview under test/components/previews (Lookbook at /lookbook).
class ApplicationComponent < ViewComponent::Base
  private

  # Lucide icon as inline SVG (rails_icons). `icon("check", class: "size-4")`.
  def icon(name, **options)
    helpers.icon(name, **options)
  end

  # Joins class fragments, dropping nils/false — `classes("btn", primary? && "btn-primary")`.
  def classes(*fragments)
    fragments.flatten.compact.reject { |c| c == false }.join(" ")
  end
end
