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

  def preview
    current = params[:url].presence || default_start_url
    html = RandomWalker::PageFrame.new(url: current).html

    response.set_header("Content-Security-Policy", preview_content_security_policy)
    response.set_header("X-Content-Type-Options", "nosniff")
    render plain: html, content_type: "text/html; charset=utf-8"
  rescue RandomWalker::PageFrame::Error => e
    response.set_header("Content-Security-Policy", preview_content_security_policy)
    render plain: preview_error_html(e.message), status: :unprocessable_entity, content_type: "text/html; charset=utf-8"
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

  def preview_content_security_policy
    [
      "default-src http: https: data: blob:",
      "script-src http: https: 'unsafe-inline' 'unsafe-eval'",
      "style-src http: https: 'unsafe-inline'",
      "img-src http: https: data: blob:",
      "font-src http: https: data:",
      "connect-src http: https:",
      "frame-src http: https:",
      "form-action http: https:",
      "sandbox allow-forms allow-modals allow-popups allow-popups-to-escape-sandbox allow-scripts"
    ].join("; ")
  end

  def preview_error_html(message)
    <<~HTML
      <!doctype html>
      <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {
              margin: 0;
              padding: 24px;
              color: #3c4354;
              font: 16px/1.6 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #fff;
            }
          </style>
        </head>
        <body>
          #{ERB::Util.html_escape(message)}
        </body>
      </html>
    HTML
  end
end
