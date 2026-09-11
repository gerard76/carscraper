class CarsController < ApplicationController

  before_action :load_car, only: [:show, :update]
  def index
    @q    = Car.ransack(search_params)
    @cars = @q.result.visible.includes(:model).order(:year)
    points = @cars.map { |car| point(car) }

    # A car whose seller left the odometer empty cannot be coloured, so it goes
    # in a series of its own: grey, with a legend entry that says why.
    @data, @unmeasured = points.partition { |point| point[:value][2] }
    @wear      = wear_range
    @trendline = trendline(points)
  end

  def show
  end

  def update
    @car.update(car_params)
    redirect_to cars_path(q: session[:q])
  end

  private

  def car_params
    params.require(:car).permit(:visible, :comments)
  end

  def load_car
    @car = Car.find(params[:id])
  end

  def point(car)
    {
      # Plot eur, not price: finn.no quotes kroner, and the search form and the
      # car page go by eur too. The third value is what the colour scale reads.
      value: [car.year.to_date.to_time.to_i * 1000, car.eur.to_f, km_per_year(car)&.round],
      url: car_path(car),
      km: car.km,
      version: car.version,
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

  # A car registered this month would divide by nearly nothing.
  MIN_AGE_IN_YEARS = 0.25

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
      values = @cars.filter_map { |car| km_per_year(car) }.sort

      if values.empty?
        [0.0, 0.0]
      else
        [values[(values.size * 0.05).floor], values[(values.size * 0.95).floor.clamp(0, values.size - 1)]]
      end
    end
  end

  def km_per_year(car)
    return nil if car.km.nil? || car.year.nil?

    car.km / [(Date.current - car.year).to_f / 365.25, MIN_AGE_IN_YEARS].max
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