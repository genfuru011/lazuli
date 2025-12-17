# frozen_string_literal: true

require "net/http"
require "uri"

def percentile(sorted, p)
  return nil if sorted.empty?
  idx = (p * (sorted.length - 1)).round
  sorted[[idx, 0].max]
end

def run_phase(name:, uri:, method:, headers: {}, form: nil, duration_s:, concurrency:)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration_s
  total = 0
  errors = 0
  sum_ms = 0.0
  max_ms = 0.0
  sample = []
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

          mutex.synchronize do
            total += 1
            errors += 1 unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
            sum_ms += dt_ms
            max_ms = dt_ms if dt_ms > max_ms
            sample << dt_ms if rand < sample_rate
          end
        rescue StandardError
          mutex.synchronize do
            total += 1
            errors += 1
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
end

base = URI(ARGV[0] || "http://127.0.0.1:9294")
duration_s = Integer(ENV.fetch("DURATION", "10"))
concurrency = Integer(ENV.fetch("CONCURRENCY", "20"))

# Keep DB growth under control for repeated runs.
run_phase(
  name: "cleanup users",
  uri: URI.join(base.to_s + "/", "users"),
  method: :delete,
  duration_s: 1,
  concurrency: 1
)

run_phase(
  name: "SSR (users index)",
  uri: URI.join(base.to_s + "/", "users"),
  method: :get,
  duration_s: duration_s,
  concurrency: concurrency
)

run_phase(
  name: "SSR + Islands (todos)",
  uri: URI.join(base.to_s + "/", "todos"),
  method: :get,
  duration_s: duration_s,
  concurrency: concurrency
)

run_phase(
  name: "Turbo Stream (POST /users)",
  uri: URI.join(base.to_s + "/", "users"),
  method: :post,
  headers: { "Accept" => "text/vnd.turbo-stream.html" },
  form: { "name" => "bench" },
  duration_s: duration_s,
  concurrency: [concurrency, 4].min
)
