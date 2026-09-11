# frozen_string_literal: true

module Payments
  module Adapters
    # Interface every payment adapter implements. Only adapters know about
    # chains, facilitators and header formats.
    class Base
      # @return [Result] success data: { payer: String }
      def verify(payload:, requirements:, extensions: nil)
        raise NotImplementedError
      end

      # @return [Result] success data: { receipt: Payments::Receipt }
      def settle(payload:, requirements:, extensions: nil)
        raise NotImplementedError
      end
    end
  end
end
