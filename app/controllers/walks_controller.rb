class WalksController < ApplicationController
  def show
    current = params[:url].presence || default_start_url
    picker = RandomWalker::LinkPicker.new(url: current)
    link = picker.next_link
    render json: { url: link.url, label: link.label, html: link.html }
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
end
