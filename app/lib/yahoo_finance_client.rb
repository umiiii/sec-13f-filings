class YahooFinanceClient
  include HTTParty

  base_uri "https://query1.finance.yahoo.com"
  default_timeout 10

  FetchError = Class.new(StandardError)

  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  def fetch_daily_closes(symbol, from:, to:)
    response = self.class.get(
      "/v8/finance/chart/#{CGI.escape(symbol)}",
      query: {
        period1: from.to_time.to_i,
        period2: (to.to_time + 86_400).to_i,
        interval: "1d",
        events: "div,splits"
      },
      headers: {"User-Agent" => USER_AGENT, "Accept" => "application/json"}
    )

    raise FetchError, "HTTP #{response.code} for #{symbol}" unless response.success?

    payload = response.parsed_response
    error = payload.dig("chart", "error")
    raise FetchError, "Yahoo error for #{symbol}: #{error}" if error

    result = payload.dig("chart", "result", 0)
    return {} if result.blank?

    timestamps = result["timestamp"] || []
    closes = result.dig("indicators", "quote", 0, "close") || []
    gmt_offset = result.dig("meta", "gmtoffset").to_i

    timestamps.zip(closes).each_with_object({}) do |(ts, close), acc|
      next if ts.nil? || close.nil?

      date = Time.at(ts + gmt_offset).utc.to_date
      acc[date] = close
    end
  end
end
