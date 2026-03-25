class WalksController < ApplicationController
  before_action :enforce_rate_limit!

  def show
    current = params[:url].presence || default_start_url
    picker = RandomWalker::LinkPicker.new(
      url: current,
      mode: walk_mode,
      visited: visited_urls,
      sweet_click: sweet_click?,
      lucky_jump: lucky_jump?,
      force_lucky_jump: force_lucky_jump?
    )
    link = picker.next_link
    render json: {
      url: link.url,
      label: link.label,
      title: link.title,
      description: link.description,
      site_name: link.site_name,
      host: link.host,
      lucky_jump: picker.lucky_jump_triggered?
    }
  rescue RandomWalker::LinkPicker::Error => e
    payload = { error: e.message }

    if e.is_a?(RandomWalker::LinkPicker::UnsafeURLError)
      payload[:unsafe] = true
      payload[:reasons] = e.reasons
      payload[:blocked_url] = e.candidate
    end

    render json: payload, status: :unprocessable_entity
  end

  private

  def default_start_url
    Rails.application.config.random_walker[:initial_url]
  end

  def walk_mode
    params[:mode].to_s == "ribbon" ? :ribbon : :default
  end

  def visited_urls
    Array(params[:visited]).filter_map do |value|
      candidate = value.to_s.strip
      candidate unless candidate.empty?
    end
  end

  def lucky_jump?
    ActiveModel::Type::Boolean.new.cast(params[:lucky])
  end

  def sweet_click?
    ActiveModel::Type::Boolean.new.cast(params[:sweet])
  end

  def force_lucky_jump?
    ActiveModel::Type::Boolean.new.cast(params[:force_lucky_jump])
  end

  def enforce_rate_limit!
    config = Rails.application.config.random_walker
    limit = config[:rate_limit_requests].to_i
    window = config[:rate_limit_window].to_i
    return if limit <= 0 || window <= 0

    key = "random-walker:walk-rate:#{request.remote_ip}:#{Time.current.to_i / window}"
    count = increment_rate_counter(key, window)
    return if count <= limit

    render json: { error: "Too many walk requests. Please slow down." }, status: :too_many_requests
  end

  def increment_rate_counter(key, window)
    count = Rails.cache.increment(key, 1, expires_in: window.seconds)
    return count if count

    count = Rails.cache.read(key).to_i + 1
    Rails.cache.write(key, count, expires_in: window.seconds)
    count
  end
end
