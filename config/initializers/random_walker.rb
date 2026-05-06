Rails.application.config.random_walker = {
  initial_url: ENV.fetch("RANDOM_WALKER_INITIAL_URL", "https://qiita.com/"),
  allowed_hosts: ENV.fetch("RANDOM_WALKER_ALLOWED_HOSTS", "").split(",").map { |host| host.strip.downcase }.reject(&:empty?),
  contact_email: ENV["RANDOM_WALKER_CONTACT_EMAIL"].presence ||
    ENV["RANDOM_WALKER_SUPPORT_EMAIL"].presence ||
    "hello@randomwalker.example",
  rate_limit_window: ENV.fetch("RANDOM_WALKER_RATE_LIMIT_WINDOW", "60").to_i,
  rate_limit_requests: ENV.fetch("RANDOM_WALKER_RATE_LIMIT_REQUESTS", "30").to_i
}
