class WalksController < ApplicationController
  def show
    current = params[:url].presence || default_start_url
    picker = RandomWalker::LinkPicker.new(url: current)
    link = picker.next_link
    render json: { url: link.url, label: link.label }
  rescue RandomWalker::LinkPicker::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def default_start_url
    Rails.application.config.random_walker[:initial_url]
  end
end
