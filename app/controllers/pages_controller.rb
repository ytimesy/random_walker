class PagesController < ApplicationController
  def home
    config = Rails.application.config.random_walker
    RandomWalker::OneYenMission.track_visit!(cookies)
    @initial_url = config[:initial_url]
    @launch_domains = config[:allowed_hosts]
    @support_email = config[:support_email]
    @support_url = config[:support_url] || "mailto:#{@support_email}?subject=Random%20Walker%20Supporter"
    @mission = RandomWalker::OneYenMission.snapshot(
      visitor_value_yen: config[:visitor_value_yen],
      support_batch_yen: config[:support_batch_yen]
    )
    @plans = [
      {
        name: "Free Drift",
        price: "Free",
        tone: "For curious visitors",
        features: [
          "One-click random walks",
          "Local saved trails",
          "JSON trail export",
          "Starter public destinations"
        ]
      },
      {
        name: "Supporter",
        price: "JPY 500/mo",
        tone: "Best first paid tier",
        features: [
          "Future cloud sync",
          "More themes and mascots",
          "Priority on new destination packs"
        ]
      },
      {
        name: "Creator Pack",
        price: "JPY 1,200/mo",
        tone: "For streamers and communities",
        features: [
          "Shareable themed routes",
          "Branded launch pages",
          "Community support channel"
        ]
      }
    ]
  end

  def pricing
    home
    render :pricing
  end

  def privacy; end

  def terms; end
end
