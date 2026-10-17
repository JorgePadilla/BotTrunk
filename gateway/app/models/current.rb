# frozen_string_literal: true

# Per-request memo. Reset by Rails before every request and job, so nothing
# here outlives the request that filled it.
class Current < ActiveSupport::CurrentAttributes
  # Live seller listings as catalog entries. Catalog::Service.all is read
  # many times per request (the page, the 402, the Bazaar entry); this keeps
  # it to one query.
  attribute :listing_services
end
