class CarsController < ApplicationController

  before_action :load_car, only: [:show, :update, :hide, :unhide, :favourite]
  before_action :remember_listing, only: [:index, :table, :photos, :bin]

  helper_method :listing_path

  def index
    @q    = Car.ransack(search_params)
    @cars = @q.result.on_offer.includes(:model).order(:year)

    scatter   = Scatter.new(@cars)
    @data     = scatter.measured
    @unmeasured = scatter.unmeasured
    @trendline  = scatter.trendline
    @floor      = scatter.floor
  end

  # The same cars as the graph, as a table. Ransack does the sorting, so the
  # column headers keep whatever is filled in on the search form.
  def table
    @q    = remember_sort(Car.ransack(search_params))
    @cars = page_of(@q.result.on_offer.includes(:model))
  end

  # The same cars again, as photographs.
  def photos
    @q    = remember_sort(Car.ransack(search_params))
    @cars = page_of(@q.result.on_offer.includes(:model))
  end

  # What you clicked away. Kept apart from what a rule hid -- the duplicates,
  # the factory-new, the batteries that are too small -- because that is a heap
  # and this is a decision.
  def bin
    @cars = Car.hidden_by_hand.includes(:model).order(updated_at: :desc)
  end

  def hide
    @car.update_columns(hidden_by: Car::BY_HAND)

    redirect_back fallback_location: photos_cars_path, notice: "Put away. It is in the bin."
  end

  def unhide
    @car.update_columns(hidden_by: nil)

    redirect_back fallback_location: bin_cars_path, notice: "Back on the pages."
  end

  # The same button on and off again. No notice: the star says it itself.
  def favourite
    @car.update_columns(favourite: !@car.favourite)

    redirect_back fallback_location: photos_cars_path
  end

  def show
  end

  def update
    changes = car_params.to_h

    # The star and the bin on a car's own page are submit buttons of the notes
    # form rather than forms of their own, so that pressing one keeps the note
    # you were halfway through instead of reloading the page out from under
    # you. Which is also why they land here and not in #hide and #unhide --
    # those are for the cross on a photo, where there is no note to lose.
    changes["favourite"] = !@car.favourite if params[:toggle_favourite]
    changes["hidden_by"] = Car::BY_HAND if params[:bin]
    changes["hidden_by"] = nil if params[:unbin]

    @car.update(changes)

    notice = if params[:bin]
               "In the bin."
             elsif params[:unbin]
               "Back on the pages."
             else
               "Saved."
             end

    redirect_back fallback_location: cars_path(q: session[:q]), notice: notice
  end

  private

  def car_params
    params.require(:car).permit(:comments)
  end

  def load_car
    @car = Car.find(params[:id])
  end

  # The list you were last looking at, filter and sort and all, so that "back"
  # on a car's own page goes where you came from.
  #
  # The referer cannot answer this. Starring a car posts from its page and
  # lands on it again, so from then on the referer *is* that page and back
  # points at itself -- which is what it did until this was here. Remembering
  # the list instead survives that round trip, and any number of them, and it
  # keeps table and graph apart rather than sending everyone to the photos.
  def remember_listing
    session[:listing] = request.fullpath
  end

  def listing_path
    session[:listing].presence || photos_cars_path
  end

  # How many cars to a page of the table and the wall.
  #
  # All of them used to go on one page, and on a desktop that was fine. On a
  # phone it was not: eleven hundred rows is 2.2 MB of html and thirty
  # thousand elements, two seconds of rendering here and a good deal more of
  # laying it out there, and every touch of a filter paid the whole bill
  # again. Fifty is a couple of screens of scrolling, and about a twentieth of
  # all that.
  #
  # The graph keeps every car. It is not a list you read down: the trend line
  # and the colour scale are statements about the whole set, and a page of it
  # would quietly be a statement about fifty cars instead.
  PER_PAGE = 50

  # One page of a list, and what the pager needs to describe it.
  #
  # @total is the whole answer, not what is in front of you -- the count line
  # says "1,096 cars" and then which of them you are looking at. The order is
  # dropped for the count: postgres would only throw it away again, and
  # landed_eur is an expression, not a column.
  #
  # A page number out of range is clamped rather than refused. Filters narrow
  # as you type: asking for six seats while standing on page 12 is an ordinary
  # thing to do, and it should land you on the last page there is, not on an
  # error.
  def page_of(scope)
    @total = scope.except(:order).count
    @pages = (@total / PER_PAGE.to_f).ceil
    @page  = params[:page].to_i.clamp(1, [@pages, 1].max)
    @from  = (@page - 1) * PER_PAGE + 1
    @to    = [@page * PER_PAGE, @total].min

    scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end

  # Cheapest first until you say otherwise.
  DEFAULT_SORT = "landed_eur asc".freeze

  # Whatever you last sorted on is what the next page opens with, this visit
  # and the ones after it, on the table and the photos alike.
  def remember_sort(query)
    chosen = params.dig(:q, :s).presence
    session[:sort] = chosen if chosen

    query.sorts = chosen || session[:sort] || DEFAULT_SORT if query.sorts.empty?
    query
  end

  # What you last filtered on, until you say otherwise.
  #
  # The sort has been remembered for a while (remember_sort) and the filters
  # were not, so every visit started with an empty form and a thousand cars:
  # six seats, 79 kWh, under 40,000 km, all of it typed in again. A bare
  # /cars/photos carries no q at all, and that is most of how you arrive --
  # from a bookmark, from the menu, from yesterday.
  #
  # Which turns the plain path into "whatever you had", so Clear has to say so
  # out loud: it asks for ?clear=1 and that is the one thing that empties this.
  def search_params
    session.delete(:q) if params[:clear]
    session[:q] = asked_for if params[:q]

    # Kept apart on purpose: this is the filter as the form speaks it, which is
    # what the boxes and the menu are drawn from, and the copy below is the
    # same thing translated into ransack's. Draw the boxes from the untranslated
    # one or they disagree with the list they sit above.
    @search_query = remembered_query
    return {} if @search_query.blank?

    q = @search_query.deep_dup

    q["g"] = groupings(q)
    q.delete("g") if q["g"].empty?

    if q[:year_min].present?
      year_start = Date.new(q.delete(:year_min).to_i, 1, 1)
      q[:year_gteq] = year_start
    end

    q
  end

  # The filter this request is to be read with: its own, or the one in hand
  # from last time. A hash either way -- what comes back out of the session
  # cookie is plain json, with none of Parameters' methods on it.
  def remembered_query
    ActiveSupport::HashWithIndifferentAccess.new(params[:q] ? asked_for : session[:q] || {})
  end

  # What the form asked for, with "Any" honoured.
  #
  # A select you can pick several things from still carries its blank "Any"
  # row, and nothing stops you from picking that *and* 6 and 7 -- which read
  # literally is "any seat count, and also six, and also seven". The blank used
  # to be dropped and the other two kept, so ticking Any left you with exactly
  # the filter you were trying to lift. Any wins instead, and takes the field
  # with it.
  def asked_for
    q = params[:q].to_unsafe_h

    PICK_SEVERAL.each do |field|
      q.delete("#{field}_in") if Array(q["#{field}_in"]).any?(&:blank?)
    end

    q
  end

  # The three the listing pages fill in. Each is asked as a select you can pick
  # more than one thing from, because six seats or seven is one question and so
  # is 79 kWh or 86.
  PICK_SEVERAL = %w[seats kwh wheelbase].freeze

  # "Not stated" is a different question from a value, and ransack asks it
  # under another name: a car that says nothing about its battery is not a car
  # that says zero. So a field where you picked it becomes an OR group of the
  # two predicates -- 79, or 86, or nothing said.
  #
  # A group per field rather than one for all of them. Ransack's own `m` would
  # put every other filter in the same OR, and then a price limit would stop
  # meaning anything; groups are ANDed with each other, so "six or seven seats"
  # and "79 kWh or unknown" still has to be both.
  def groupings(q)
    PICK_SEVERAL.filter_map do |field|
      picked = Array(q.delete("#{field}_in")).reject(&:blank?)
      next if picked.empty?

      unless picked.delete(CarsHelper::NOT_STATED)
        q["#{field}_in"] = picked
        next
      end

      if picked.any?
        { "m" => "or", "#{field}_in" => picked, "#{field}_null" => "1" }
      else
        { "#{field}_null" => "1" }
      end
    end
  end
end