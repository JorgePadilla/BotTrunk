# frozen_string_literal: true

# The one email a buyer gets: proof that asking for something reached a person.
# The alternative was a mailto: link pointing at an address the domain does not
# receive mail on, which bounced silently.
class BuyerMailer < ApplicationMailer
  def acknowledgement
    @request = params[:request]

    mail(to: @request.email, subject: subject_for(@request))
  end

  private

  def subject_for(request)
    return "We got your request — #{request.service.name}" if request.service

    "We got your request"
  end
end
