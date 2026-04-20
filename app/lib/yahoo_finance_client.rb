class YahooFinanceClient
  include HTTParty

  base_uri "https://stooq.com"
  default_timeout 10

  FetchError = Class.new(StandardError)

  def fetch_daily_closes(symbol, from:, to:)
    stooq_symbol = to_stooq_symbol(symbol)
    response = self.class.get(
      "/q/d/l/",
      query: {
        s: stooq_symbol,
        i: "d",
        d1: from.strftime("%Y%m%d"),
        d2: to.strftime("%Y%m%d")
      },
      headers: {"Accept" => "text/csv"}
    )

    raise FetchError, "HTTP #{response.code} for #{symbol}" unless response.success?

    body = response.body.to_s
    return {} if body.blank? || body.start_with?("No data")

    lines = body.split("\n").map(&:strip).reject(&:empty?)
    return {} if lines.size <= 1

    header = lines.shift.split(",")
    date_idx = header.index("Date")
    close_idx = header.index("Close")
    return {} unless date_idx && close_idx

    lines.each_with_object({}) do |line, acc|
      cols = line.split(",")
      date_str = cols[date_idx]
      close_str = cols[close_idx]
      next if date_str.blank? || close_str.blank? || close_str == "N/D"

      begin
        acc[Date.parse(date_str)] = BigDecimal(close_str)
      rescue ArgumentError, TypeError
        next
      end
    end
  end

  private

  def to_stooq_symbol(symbol)
    "#{symbol.downcase.tr('.', '-')}.us"
  end
end
