class StockPriceFetcher
  CACHE_LOOKBACK_DAYS = 14

  def self.prices_for_filing(filing)
    new(filing).call
  end

  def initialize(filing, yahoo_client: YahooFinanceClient.new)
    @filing = filing
    @yahoo_client = yahoo_client
  end

  def call
    return {} if filing.report_date.blank? || filing.date_filed.blank?

    target_dates = compute_target_dates
    cusips_by_symbol = resolve_symbols

    return {} if cusips_by_symbol.empty?

    ensure_cached!(cusips_by_symbol.keys, target_dates)
    prices_by_symbol = load_prices(cusips_by_symbol.keys, target_dates)

    cusips_by_symbol.each_with_object({}) do |(symbol, cusips), result|
      entry = prices_by_symbol[symbol] || {}
      cusips.each { |cusip| result[cusip] = entry }
    end
  end

  private

  attr_reader :filing, :yahoo_client

  def compute_target_dates
    {
      filed: filing.date_filed - 1,
      as_of: filing.report_date - 1,
      now: Date.current - 1
    }
  end

  def resolve_symbols
    cusips = filing.holdings.
      where(shares_or_principal_amount_type: "sh", option_type: nil).
      distinct.
      pluck(:cusip)

    return {} if cusips.empty?

    CusipSymbolMapping.
      where(cusip: cusips).
      where.not(symbol: [nil, ""]).
      pluck(:symbol, :cusip).
      each_with_object({}) do |(symbol, cusip), acc|
        (acc[symbol] ||= []) << cusip
      end
  end

  def ensure_cached!(symbols, target_dates)
    existing_dates = StockPrice.
      where(symbol: symbols).
      pluck(:symbol, :date).
      group_by(&:first).
      transform_values { |pairs| pairs.map(&:last) }

    fetch_from = target_dates.values.min - CACHE_LOOKBACK_DAYS
    fetch_to = target_dates.values.max

    symbols.each do |symbol|
      known = existing_dates[symbol] || []
      missing = target_dates.values.any? { |target| known.none? { |d| d <= target } }
      next unless missing

      closes = safe_fetch(symbol, from: fetch_from, to: fetch_to)
      next if closes.blank?

      StockPrice.bulk_upsert(symbol, closes)
    end
  end

  def safe_fetch(symbol, from:, to:)
    yahoo_client.fetch_daily_closes(symbol, from: from, to: to)
  rescue YahooFinanceClient::FetchError, Timeout::Error, SocketError, Errno::ECONNRESET => e
    Rails.logger.warn "[StockPriceFetcher] #{symbol}: #{e.class}: #{e.message}"
    nil
  end

  def load_prices(symbols, target_dates)
    symbols.each_with_object({}) do |symbol, acc|
      acc[symbol] = target_dates.transform_values do |target|
        StockPrice.close_on_or_before(symbol, target)
      end
    end
  end
end
