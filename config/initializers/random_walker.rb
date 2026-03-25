Rails.application.config.random_walker = {
  initial_url: ENV.fetch("RANDOM_WALKER_INITIAL_URL", "https://qiita.com/"),
  allowed_hosts: ENV.fetch("RANDOM_WALKER_ALLOWED_HOSTS", "").split(",").map { |host| host.strip.downcase }.reject(&:empty?),
  support_email: ENV.fetch("RANDOM_WALKER_SUPPORT_EMAIL", "hello@randomwalker.example"),
  support_url: ENV["RANDOM_WALKER_SUPPORT_URL"].presence,
  visitor_value_yen: ENV.fetch("RANDOM_WALKER_VISITOR_VALUE_YEN", "1").to_i,
  support_batch_yen: ENV.fetch("RANDOM_WALKER_SUPPORT_BATCH_YEN", "100").to_i,
  rate_limit_window: ENV.fetch("RANDOM_WALKER_RATE_LIMIT_WINDOW", "60").to_i,
  rate_limit_requests: ENV.fetch("RANDOM_WALKER_RATE_LIMIT_REQUESTS", "30").to_i
}
