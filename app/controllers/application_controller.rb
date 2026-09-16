class ApplicationController < ActionController::Base
  # The filter as it came in, as a plain hash: strong parameters refuses to
  # hand an unpermitted one to a url helper, and the menu carries whatever is
  # filled in from one page to the next.
  helper_method :search_query

  private

  def search_query
    request.query_parameters[:q]
  end
end
