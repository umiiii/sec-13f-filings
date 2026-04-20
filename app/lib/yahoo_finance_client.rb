class YahooFinanceClient
  FetchError = Class.new(StandardError)

  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  CHART_BASE = "https://query1.finance.yahoo.com/v8/finance/chart"
  CRUMB_URL  = "https://query1.finance.yahoo.com/v1/test/getcrumb"
  COOKIE_URL = "https://fc.yahoo.com/"

  def fetch_daily_closes(symbol, from:, to:)
    ensure_session!

    uri = URI("#{CHART_BASE}/#{CGI.escape(symbol)}")
    uri.query = URI.encode_www_form(
      period1: from.to_time.to_i,
      period2: (to.to_time + 86_400).to_i,
      interval: "1d",
      crumb: @crumb
    )

    response = http_get(uri)

    if response.code.to_i == 401
      reset_session!
      ensure_session!
      uri.query = URI.encode_www_form(
        period1: from.to_time.to_i,
        period2: (to.to_time + 86_400).to_i,
        interval: "1d",
        crumb: @crumb
      )
      response = http_get(uri)
    end

    raise FetchError, "HTTP #{response.code} for #{symbol}" unless response.code.to_i == 200

    payload = JSON.parse(response.body)
    error = payload.dig("chart", "error")
    raise FetchError, "Yahoo error for #{symbol}: #{error}" if error

    result = payload.dig("chart", "result", 0)
    return {} if result.blank?

    timestamps = result["timestamp"] || []
    closes = result.dig("indicators", "quote", 0, "close") || []
    gmt_offset = result.dig("meta", "gmtoffset").to_i

    timestamps.zip(closes).each_with_object({}) do |(ts, close), acc|
      next if ts.nil? || close.nil?
      acc[Time.at(ts + gmt_offset).utc.to_date] = close
    end
  end

  private

  def ensure_session!
    return if @cookie && @crumb

    cookie_resp = http_get(URI(COOKIE_URL))
    @cookie = extract_cookie(cookie_resp)

    crumb_resp = http_get(URI(CRUMB_URL))
    @crumb = crumb_resp.body.to_s.strip
    raise FetchError, "empty crumb" if @crumb.empty?
  end

  def reset_session!
    @cookie = nil
    @crumb = nil
  end

  def http_get(uri)
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "*/*"
    req["Cookie"] = @cookie if @cookie

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(req)
    end
  end

  def extract_cookie(response)
    headers = response.get_fields("set-cookie") || []
    headers.map { |h| h.split(";", 2).first }.join("; ")
  end
end
