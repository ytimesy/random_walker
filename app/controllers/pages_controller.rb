class PagesController < ApplicationController
  def home
    @initial_url = Rails.application.config.random_walker[:initial_url]
  end
end
