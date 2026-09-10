# frozen_string_literal: true

# The return value of every service object.
#
#   Result.success(payer: "ABC…")      #=> success? true,  data = { payer: … }
#   Result.failure("invalid", code: :invalid_payment)
Result = Data.define(:success, :data, :error, :code) do
  def self.success(data = {}) = new(success: true, data: data, error: nil, code: nil)
  def self.failure(error, code: :error, data: {}) = new(success: false, data: data, error: error, code: code)

  def success? = success
  def failure? = !success

  # result[:payer] reads from data.
  def [](key) = data[key]
end
