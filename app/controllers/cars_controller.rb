class CarsController < ApplicationController

  def index
    @model = Model.find(2)
    @cars = []
    @maxprice = 0
    @minprice = @model.cars.maximum(:eur)
    @q = @model.cars.ransack(params[:q])
    @q.result.for_graph.each do |country, cars|
      data = cars.map do |car|
        @minprice = car.eur if car.eur < @minprice
        @maxprice = car.eur if car.eur > @maxprice
        [car.year, car.eur ]
      end
      @cars << { name: country, data: data }
    end
# raise @cars.inspect
    @minprice = @minprice.floor(-4)
    @maxprice = @maxprice.ceil(-4)
  end
end