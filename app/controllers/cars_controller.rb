class CarsController < ApplicationController

  def index
    # @model = Model.find(params[:id])
    @q = Car.ransack(params[:q])
    @cars = @q.result.visible.order(:year)

    @data = @cars.map do |car|
      {
        value: [car.year.strftime("%Y-%m"), car.price.to_f],
        url: car.url,
        km: car.km
      }
    end
  end
end