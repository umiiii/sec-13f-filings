class YahooFinanceClient
  include HTTParty

  base_uri "https://api.twelvedata.com"
  default_timeout 15

  FetchError = Class.new(StandardError)

  def fetch_daily_closes(symbol, from:, to:)
    response = self.class.get(
      "/time_series",
      query: {
        symbol: symbol,
        interval: "1day",
        start_date: from.strftime("%Y-%m-%d"),
        end_date: to.strftime("%Y-%m-%d"),
        order: "asc",
        apikey: api_key
      }
    )

    raise FetchError, "HTTP #{response.code} for #{symbol}" unless response.success?

    payload = response.parsed_response
    if payload["status"] == "error"
      raise FetchError, "TwelveData error for #{symbol}: #{payload['code']} #{payload['message']}"
    end

    values = payload["values"] || []
    values.each_with_object({}) do |v, acc|
      date_str = v["datetime"]
      close_str = v["close"]
      next if date_str.blank? || close_str.blank?

      acc[Date.parse(date_str)] = BigDecimal(close_str)
    end
  end

  private

  def api_key
    key = ENV["TWELVE_DATA_API_KEY"]
    raise FetchError, "TWELVE_DATA_API_KEY not set" if key.blank?
    key
  end
end
