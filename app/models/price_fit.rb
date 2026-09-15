# What a car ought to cost, going by the other cars on the graph: a least
# squares plane through price, build year and mileage. What a car asks less
# than the plane expects is its bargain -- cheap for its age and for how far
# it has driven, which is not the same as cheap.
#
# Trim level is not in the fit, so a bare Pure comes out looking like a find
# next to a GTX of the same year and mileage.
class PriceFit
  # Below this there is nothing to compare a car against.
  MIN_CARS = 3

  def initialize(cars)
    @cars = Array(cars).select { |car| comparable?(car) }
    fit
  end

  def fitted?
    !@intercept.nil?
  end

  # What the fit expects this car to cost, in euro, or nil when it cannot say.
  def expected(car)
    return nil unless fitted? && comparable?(car)

    @intercept + @per_year * years(car) + @per_km * car.km
  end

  # How much less than that it asks: positive is cheap for its age and mileage,
  # negative is dear.
  def bargain(car)
    expectation = expected(car)
    return nil if expectation.nil?

    (expectation - car.landed_eur).round
  end

  # What the fit makes of a year of age and of a thousand kilometres, both in
  # euro. Worth a look when the numbers come out strange.
  def coefficients
    { per_year: @per_year&.round, per_1000_km: @per_km && (@per_km * 1000).round }
  end

  private

  def comparable?(car)
    car.eur.present? && car.km.present? && car.year.present?
  end

  # Decimal years: 2024-07-01 becomes 2024.5. Small enough to square without
  # losing precision, and it makes @per_year a price drop per year.
  def years(car)
    car.year.year + (car.year.month - 1) / 12.0
  end

  def fit
    return if @cars.size < MIN_CARS

    n  = @cars.size.to_f
    xs = @cars.map { |car| years(car) }
    zs = @cars.map { |car| car.km.to_f }
    ys = @cars.map { |car| car.landed_eur.to_f }

    mean_x, mean_z, mean_y = xs.sum / n, zs.sum / n, ys.sum / n
    dx = xs.map { |x| x - mean_x }
    dz = zs.map { |z| z - mean_z }
    dy = ys.map { |y| y - mean_y }

    sxx = dx.sum { |x| x * x }
    szz = dz.sum { |z| z * z }
    sxz = dx.zip(dz).sum { |x, z| x * z }
    sxy = dx.zip(dy).sum { |x, y| x * y }
    szy = dz.zip(dy).sum { |z, y| z * y }

    # Singular when every car shares a year or a mileage, or when the two run
    # exactly together. There is no plane to fit then.
    determinant = sxx * szz - sxz * sxz
    return if determinant.abs <= sxx * szz * Float::EPSILON

    @per_year  = (sxy * szz - szy * sxz) / determinant
    @per_km    = (szy * sxx - sxy * sxz) / determinant
    @intercept = mean_y - @per_year * mean_x - @per_km * mean_z
  end
end
