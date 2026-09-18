class CarsController < ApplicationController

  before_action :load_car, only: [:show, :update, :hide, :unhide, :favourite]
  before_action :remember_listing, only: [:index, :table, :photos, :bin]

  helper_method :listing_path

  def index
    @q    = Car.ransack(search_params)
    @cars = @q.result.on_offer.includes(:model).order(:year)
    points = @cars.map { |car| point(car) }

    # A car whose seller left the odometer empty cannot be coloured, so it goes
    # in a series of its own: grey, with a legend entry that says why.
    @data, @unmeasured = points.partition { |point| point[:value][2] }
    @trendline = trendline(points)
    @floor     = (points.map { |point| point[:value][1] }.min || 1_000) - 1_000
  end

  # The same cars as the graph, as a table. Ransack does the sorting, so the
  # column headers keep whatever is filled in on the search form.
  def table
    @q    = remember_sort(Car.ransack(search_params))
    @cars = @q.result.on_offer.includes(:model)
  end

  # The same cars again, as photographs.
  def photos
    @q    = remember_sort(Car.ransack(search_params))
    @cars = @q.result.on_offer.includes(:model)
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

  def point(car)
    {
      # Plot what the car costs you: the asking price in euro plus what it
      # takes to get it here, which is the whole point of looking abroad. The
      # third value is what the colour scale reads.
      value: [car.year.to_date.to_time.to_i * 1000, car.landed_eur.to_f, car.km_per_year&.round],
      itemStyle: { color: wear_color(car) },
      url: car_path(car),
      asked: car.eur,
      import: car.import_costs,
      distance: car.distance_km,
      bargain: car.bargain_eur,
      km: car.km,
      version: car.title,
      type: car.type,
      comments: car.comments
    }
  end

  # A straight line through price and year, as a guide for the eye: a car under
  # it asks less than its build year suggests.
  def trendline(points)
    xs = points.map { |point| point[:value][0] / 1000.0 } # back to seconds
    ys = points.map { |point| point[:value][1] }
    return [] if xs.size < 2

    n      = xs.size
    sum_x  = xs.sum
    sum_y  = ys.sum
    sum_xy = xs.zip(ys).sum { |x, y| x * y }
    sum_xx = xs.sum { |x| x * x }

    # Zero when every car shares a build date: no line to draw through those.
    denominator = n * sum_xx - sum_x**2
    return [] if denominator.zero?

    a = (n * sum_xy - sum_x * sum_y) / denominator
    b = (sum_y - a * sum_x) / n

    [[xs.min * 1000, a * xs.min + b], [xs.max * 1000, a * xs.max + b]]
  end

  # Green: driven gently for its age, red: driven hard.
  WEAR_COLORS = %w[#00e676 #76ff03 #c6ff00 #ffee58 #ffc400 #ff6d00 #ff1744].freeze

  def wear_color(car)
    per_year = car.km_per_year
    return nil if per_year.nil?

    low, high = wear_range
    return WEAR_COLORS.first if high <= low

    step  = (high - low) / WEAR_COLORS.size
    index = ((per_year - low) / step).floor.clamp(0, WEAR_COLORS.size - 1)
    WEAR_COLORS[index]
  end

  # The stretch of mileage per year the colours run over: the 5th to the 95th
  # percentile of what is on screen, so one absurd listing cannot flatten them.
  #
  # Mileage per year is coloured rather than the odometer reading itself. That
  # reading runs with the build year on the x axis (correlation -0.68 over 2000
  # ID. Buzz listings), so colouring it would mostly repeat what the position
  # already shows. Mileage per year hardly does (0.10), and it is just as
  # independent of the distance to the trend line, so it tells you something
  # the graph cannot show twice: under the line and green is cheap and gently
  # used, under the line and red is cheap because it has been hammered.
  def wear_range
    @wear_range ||= begin
      values = @cars.filter_map { |car| car.km_per_year }.sort

      if values.empty?
        [0.0, 0.0]
      else
        [values[(values.size * 0.05).floor], values[(values.size * 0.95).floor.clamp(0, values.size - 1)]]
      end
    end
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

  def search_params
    session[:q] = params[:q]
    return {} unless params[:q]

    q = params[:q].dup

    if q[:year_min].present?
      year_start = Date.new(q.delete(:year_min).to_i, 1, 1)
      q[:year_gteq] = year_start
    end

    q
  end
end