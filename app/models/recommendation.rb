class Recommendation < ApplicationRecord
  belongs_to :pool

  validates :strategy, :target_temp, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def series = Array(details&.dig("series"))
end
