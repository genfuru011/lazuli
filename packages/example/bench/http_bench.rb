# frozen_string_literal: true

require "net/http"
require "uri"

def percentile(sorted, p)
  return nil if sorted.empty?
  idx = (p * (sorted.length - 1)).round
  sorted[[idx, 0].max]
end

def parse_server_timing(value)
  return {} if value.to_s.strip.empty?

  out = {}
  value.split(",").each do |part|
    item = part.strip
    next if item.empty?

    name, *attrs = item.split(";").map(&:strip)
    next if name.to_s.empty?

    dur = nil
    attrs.each do |a|
      k, v = a.split("=", 2).map(&:strip)
      next unless k == "dur"
      dur = v.to_f
    end

    out[name] = dur if dur
  end
  out
end

def run_phase(name:, uri:, method:, headers: {}, form: nil, duration_s:, concurrency:)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration_s
  total = 0
  errors = 0
  sum_ms = 0.0
  max_ms = 0.0
  sample = []
  timing = Hash.new { |h, k| h[k] = [] }
  status_counts = Hash.new(0)
  sample_rate = 0.01
  mutex = Mutex.new

  threads = concurrency.times.map do
    Thread.new do
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 2
      http.read_timeout = 5

      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        begin
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          req = case method
                when :get
                  Net::HTTP::Get.new(uri)
                when :post
                  r = Net::HTTP::Post.new(uri)
                  r.set_form_data(form || {})
                  r
                when :delete
                  Net::HTTP::Delete.new(uri)
                else
                  raise "unsupported method: #{method}"
                end
          headers.each { |k, v| req[k] = v }

          res = http.request(req)
          dt_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0

          sampled = rand < sample_rate
          st = sampled ? parse_server_timing(res["server-timing"]) : {}

          ok = res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
          code = res.code.to_s

          mutex.synchronize do
            total += 1
            errors += 1 unless ok
            status_counts[code] += 1
            sum_ms += dt_ms
            max_ms = dt_ms if dt_ms > max_ms
            sample << dt_ms if sampled
            st.each { |k, v| timing[k] << v }
          end
        rescue StandardError
          mutex.synchronize do
            total += 1
            errors += 1
            status_counts["exception"] += 1
          end
        end
      end
    end
  end

  threads.each(&:join)

  avg_ms = total.zero? ? 0.0 : (sum_ms / total)
  rps = duration_s.zero? ? 0.0 : (total / duration_s)

  sorted = sample.sort
  p50 = percentile(sorted, 0.50)
  p95 = percentile(sorted, 0.95)

  puts "\n== #{name} =="
  puts "#{method.to_s.upcase} #{uri}  (#{duration_s}s, concurrency=#{concurrency})"
  puts "requests: #{total}  errors: #{errors}  rps: #{format('%.1f', rps)}"
  puts "avg: #{format('%.1f', avg_ms)}ms  max: #{format('%.1f', max_ms)}ms  p50~: #{p50&.round(1)}ms  p95~: #{p95&.round(1)}ms  (sampled)"

  if errors > 0
    top = status_counts.sort_by { |_, v| -v }.first(8)
    puts "status breakdown: #{top.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  unless timing.empty?
    puts "server-timing (sampled):"
    timing.keys.sort.each do |k|
      vals = timing[k].sort
      next if vals.empty?
      puts "  #{k}: avg #{format('%.1f', vals.sum / vals.length)}ms  p95~ #{percentile(vals, 0.95)&.round(1)}ms"
    end
  end
end

base = URI(ARGV[0] || "http://127.0.0.1:9294")
duration_s = Integer(ENV.fetch("DURATION", "10"))
concurrency = Integer(ENV.fetch("CONCURRENCY", "20"))

# Keep DB growth under control for repeated runs.
run_phase(
  name: "cleanup todos",
  uri: URI.join(base.to_s + "/", "todos"),
  method: :delete,
  duration_s: 1,
  concurrency: 1
)

run_phase(
  name: "Hello World (no renderer)",
  uri: URI.join(base.to_s + "/", "hello"),
  method: :get,
  duration_s: duration_s,
  concurrency: concurrency
)

run_phase(
  name: "SSR (todos index)",
  uri: URI.join(base.to_s + "/", "todos"),
  method: :get,
  duration_s: duration_s,
  concurrency: concurrency
)

run_phase(
  name: "SSR + Islands (home)",
  uri: URI.join(base.to_s + "/", ""),
  method: :get,
  duration_s: duration_s,
  concurrency: concurrency
)

run_phase(
  name: "Turbo Stream (POST /todos)",
  uri: URI.join(base.to_s + "/", "todos"),
  method: :post,
  headers: { "Accept" => "text/vnd.turbo-stream.html" },
  form: { "text" => "bench" },
  duration_s: duration_s,
  concurrency: [concurrency, 4].min
)
