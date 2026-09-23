class ApplicationController < ActionController::Base
  # Anyone may look at the cars; only someone with the password may change
  # anything. Which is every request that is not a plain read: crossing a car
  # away, putting one back, saving a note, and the whole models scaffold.
  #
  # Basic auth rather than a login page, because there is one password and it
  # is shared. The browser asks for it the first time something is clicked and
  # remembers it after that.
  #
  # CARSCRAPER_PASSWORD unset means nothing is locked, which is how it runs on
  # your own machine. The deployed copy is given one -- see .kamal/secrets.
  before_action :lock_the_writing, unless: :reading?

  # The filter as it came in, as a plain hash: strong parameters refuses to
  # hand an unpermitted one to a url helper, and the menu carries whatever is
  # filled in from one page to the next.
  helper_method :search_query

  private

  # What the form shows as filled in, and what the menu carries from one view
  # to the next. The session half matters as much as the url half: a filter
  # remembered from yesterday has to show in the boxes, or the page says one
  # thing and the list another.
  def search_query
    request.query_parameters[:q] || session[:q]
  end

  def reading?
    request.get? || request.head?
  end

  def lock_the_writing
    password = ENV["CARSCRAPER_PASSWORD"].presence or return

    authenticate_or_request_with_http_basic("carscraper") do |_name, given|
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, password)
    end
  end
end
