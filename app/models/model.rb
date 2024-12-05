class Model < ApplicationRecord

  ### ASSOCIATIONS:
  has_many :cars,
    dependent: :destroy

  ### INSTANCE METHODS:
  def type
    "#{make} #{model}"
  end

end
