class PagesController < ApplicationController
  before_action :set_page_config, only: %i[home privacy]

  def home; end

  def privacy; end

  def terms; end

  private

  def set_page_config
    config = Rails.application.config.random_walker
    @initial_url = config[:initial_url]
    @launch_domains = config[:allowed_hosts]
    @contact_email = config[:contact_email]
  end
end
