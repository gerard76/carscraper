class CarsController < ApplicationController

  before_action :load_car, only: [:show, :update]
  def index
    session[:q] = params[:q]
    @q = Car.ransack(params[:q])
    @cars = @q.result.visible.order(:year)

    @data = @cars.map do |car|
      {
        value: [car.year.strftime("%Y-%m"), car.price.to_f],
        url: car_path(car),
        km: car.km,
        version: car.version
      }
    end
  end

  def show
  end

  def update
    @car.update(car_params)
    redirect_to cars_path(q: session[:q])
  end

  private

  def car_params
    params.require(:car).permit(:visible)
  end

  def load_car
    @car = Car.find(params[:id])
  end
end