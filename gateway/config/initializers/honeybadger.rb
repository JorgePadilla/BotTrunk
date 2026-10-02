# Honeybadger keeps its own filter list (only passwords by default). Hand it
# Rails' list so params and request headers are scrubbed the same way the logs
# are: the signed transaction in PAYMENT-SIGNATURE / X-PAYMENT and bank details
# in deposit bodies never leave the server.
Honeybadger.configure do |config|
  config.request.filter_keys += Rails.application.config.filter_parameters
end
