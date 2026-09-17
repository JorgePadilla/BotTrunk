# frozen_string_literal: true

# /sell carries two forms that post to different places: sellers offering an
# endpoint, buyers asking for work. Whichever one a visitor got wrong, the
# page still has to render both — so the ivars for both are set in one place
# rather than in whichever controller happened to fail.
module RendersSellPage
  extend ActiveSupport::Concern

  private

  def sell_page(inquiry: nil, request: nil)
    @inquiry = inquiry || SellerInquiry.new
    @request = request || ServiceRequest.new
    @submitted = false
    @requested = false
    # `on_request?` reads the real status; `live?` honours the suite-wide
    # treat_all_live flag and would make this list empty in tests.
    @arrangeable = Catalog::Service.all.select(&:on_request?)
  end
end
