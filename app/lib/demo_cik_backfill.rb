class DemoCikBackfill
  OPENFIGI_URL = "https://api.openfigi.com/v3/mapping".freeze

  def self.run!(cik)
    new(cik).call
  end

  def initialize(cik)
    @cik = cik
  end

  def call
    Rails.logger.info "[DemoCikBackfill] starting for CIK #{@cik}"
    backfill_cusip_mappings
    prefetch_prices
    Rails.logger.info "[DemoCikBackfill] done"
  end

  private

  def cusips
    @cusips ||= Holding.joins(:thirteen_f).
      where(thirteen_fs: {cik: @cik}).
      where(shares_or_principal_amount_type: "sh", option_type: nil).
      distinct.pluck(:cusip)
  end

  def backfill_cusip_mappings
    missing = cusips - CusipSymbolMapping.pluck(:cusip)
    return if missing.empty?

    Rails.logger.info "[DemoCikBackfill] looking up #{missing.size} cusips via openfigi"
    uri = URI(OPENFIGI_URL)

    missing.each_slice(10) do |batch|
      body = batch.map { |c| {idType: "ID_CUSIP", idValue: c} }
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = body.to_json
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }

      unless resp.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "[DemoCikBackfill] openfigi http #{resp.code}: #{resp.body[0..200]}"
        sleep 5
        next
      end

      now = Time.current
      rows = JSON.parse(resp.body).each_with_index.map do |r, i|
        hit = r["data"]&.first
        next unless hit && hit["ticker"]
        {cusip: batch[i], symbol: hit["ticker"], name: hit["name"], exchange: hit["exchCode"], created_at: now, updated_at: now}
      end.compact

      CusipSymbolMapping.upsert_all(rows, unique_by: :cusip) if rows.any?
      sleep 1
    end

    CompanyCusipLookup.refresh!
  end

  def prefetch_prices
    mapping = CusipSymbolMapping.where(cusip: cusips).pluck(:cusip, :symbol).to_h
    symbols = cusips.map { |c| mapping[c] }.compact.uniq
    already = StockPrice.where(symbol: symbols).distinct.pluck(:symbol)
    to_fetch = symbols - already

    return if to_fetch.empty?

    Rails.logger.info "[DemoCikBackfill] prefetching #{to_fetch.size} symbols from twelvedata"
    client = YahooFinanceClient.new
    from = Date.today - 365
    to = Date.today

    to_fetch.each_with_index do |symbol, i|
      begin
        closes = client.fetch_daily_closes(symbol, from: from, to: to)
        StockPrice.bulk_upsert(symbol, closes) if closes.any?
        Rails.logger.info "[DemoCikBackfill] #{symbol}: #{closes.size} closes"
      rescue => e
        Rails.logger.warn "[DemoCikBackfill] #{symbol}: #{e.message}"
      end
      sleep 8 if i < to_fetch.size - 1
    end
  end
end
