class StockPrice < ApplicationRecord
  validates :symbol, :date, presence: true

  scope :for_symbol, ->(symbol) { where(symbol: symbol) }

  def self.close_on_or_before(symbol, target_date)
    where(symbol: symbol).
      where("date <= ?", target_date).
      order(date: :desc).
      limit(1).
      pick(:close)
  end

  def self.bulk_upsert(symbol, closes_by_date)
    return if closes_by_date.blank?

    now = Time.current
    rows = closes_by_date.map do |date, close|
      {symbol: symbol, date: date, close: close, created_at: now, updated_at: now}
    end

    upsert_all(rows, unique_by: [:symbol, :date])
  end
end
