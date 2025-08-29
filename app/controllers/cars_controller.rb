class CarsController < ApplicationController

  before_action :load_car, only: [:show, :update]
  def index
    session[:q] = params[:q]
    @q = Car.ransack(params[:q])
    @cars = @q.result.visible.order(:year)

    @data = @cars.map do |car|
      {
        value: [car.year.to_date.to_time.to_i * 1000, car.price.to_f],
        url: car_path(car),
        km: car.km,
        version: car.version,
        type: car.type,
        comments: car.comments
      }
    end
    xs = @data.map { |p| p[:value][0] / 1000.0 } # terug naar seconden voor berekening
    ys = @data.map { |p| p[:value][1] }
    n = xs.size

    sum_x = xs.sum
    sum_y = ys.sum
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
end