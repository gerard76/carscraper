class CarsController < ApplicationController

  before_action :load_car, only: [:show, :update]
  def index
    @cars = @q.result.visible.order(:year)

    @q    = Car.ransack(search_params)
    @data = @cars.map do |car|
      {
        value: [car.year.to_date.to_time.to_i * 1000, car.price.to_f],
        url: car_path(car),
        km: car.km,
        version: car.version,
        type: car.type,
        comments: car.comments
        itemStyle: { color: km_color(@cars, car) }
      }
    end
    xs = @data.map { |p| p[:value][0] / 1000.0 } # terug naar seconden voor berekening
    ys = @data.map { |p| p[:value][1] }
    n = xs.size

    sum_x = xs.sum    sum_y = ys.sum
    sum_xy = xs.zip(ys).map { |x, y| x*y }.sum
    sum_xx = xs.map { |x| x*x }.sum

    a = (n * sum_xy - sum_x*sum_y).to_f / (n*sum_xx - sum_x**2)
    b = (sum_y - a*sum_x).to_f / n

    min_x = xs.min
    max_x = xs.max

    @trendline = [
      [min_x*1000, a*min_x + b], # in ms
      [max_x*1000, a*max_x + b]
    ]
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

  def km_color(cars, car)
    max_km = cars.maximum(:km).to_f
    min_km = cars.minimum(:km).to_f
    step_size = (max_km - min_km) / 10.0
    index = [(car.km - min_km) / step_size, 9].min.to_i

    colors = [
      '#00ff00', '#66ff00', '#ccff00', '#ffff00', '#ffcc00',
      '#ff9900', '#ff6600', '#ff3300', '#ff0000', '#990000'
    ]

    colors[index]
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