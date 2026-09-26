# The graph on /cars: the cars as points, the line drawn through them, and the
# colour that says how hard each one has been driven for its age.
#
# A class of its own for the same reason PriceFit is one: this is arithmetic
# over the whole set of cars, and none of it has anything to do with a request.
# The controller asks it four things and hands the answers to echarts.
class Scatter
  include Rails.application.routes.url_helpers

  # Green: driven gently for its age, red: driven hard.
  WEAR_COLORS = %w[#00e676 #76ff03 #c6ff00 #ffee58 #ffc400 #ff6d00 #ff1744].freeze

  # The stretch of mileage per year the colours run over: the 5th to the 95th
  # percentile of what is on screen, so one absurd listing cannot flatten them.
  LOWEST  = 0.05
  HIGHEST = 0.95

  # Room under the cheapest car, so its point does not sit on the axis.
  MARGIN = 1_000

  def initialize(cars)
    @cars = Array(cars)
  end

  # The cars that can be coloured, and the ones that cannot. A seller who left
  # the odometer empty gives us no mileage per year, so that car goes in a
  # series of its own -- grey, with a legend entry that says why.
  def measured   = coloured.first
  def unmeasured = coloured.last

  # A straight line through price and year, as a guide for the eye: a car under
  # it asks less than its build year suggests.
  def trendline
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

  # Where the price axis starts.
  def floor
    (points.map { |point| point[:value][1] }.min || MARGIN) - MARGIN
  end

  private

  attr_reader :cars

  def points
    @points ||= cars.map { |car| point(car) }
  end

  def coloured
    @coloured ||= points.partition { |point| point[:value][2] }
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

  def wear_color(car)
    per_year = car.km_per_year
    return nil if per_year.nil?

    low, high = wear_range
    return WEAR_COLORS.first if high <= low

    step  = (high - low) / WEAR_COLORS.size
    index = ((per_year - low) / step).floor.clamp(0, WEAR_COLORS.size - 1)
    WEAR_COLORS[index]
  end

  # Mileage per year is coloured rather than the odometer reading itself. That
  # reading runs with the build year on the x axis (correlation -0.68 over 2000
  # ID. Buzz listings), so colouring it would mostly repeat what the position
  # already shows. Mileage per year hardly does (0.10), and it is just as
  # independent of the distance to the trend line, so it tells you something
  # the graph cannot show twice: under the line and green is cheap and gently
  # used, under the line and red is cheap because it has been hammered.
  def wear_range
    @wear_range ||= begin
      values = cars.filter_map { |car| car.km_per_year }.sort

      if values.empty?
        [0.0, 0.0]
      else
        [values[(values.size * LOWEST).floor], values[(values.size * HIGHEST).floor.clamp(0, values.size - 1)]]
      end
    end
  end
end
