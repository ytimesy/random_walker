class EngagementEventsController < ApplicationController
  EVENT_METRICS = {
    "support_click" => :support_clicks,
    "trail_save" => :trail_saves,
    "trail_export" => :trail_exports
  }.freeze

  def create
    metric = EVENT_METRICS[params[:event_type].to_s]
    return render json: { error: "Unsupported event type." }, status: :unprocessable_entity unless metric

    RandomWalker::OneYenMission.increment!(metric)

    render json: {
      ok: true,
      mission: RandomWalker::OneYenMission.snapshot(
        visitor_value_yen: mission_config[:visitor_value_yen],
        support_batch_yen: mission_config[:support_batch_yen]
      )
    }
  end

  private

  def mission_config
    Rails.application.config.random_walker
  end
end
