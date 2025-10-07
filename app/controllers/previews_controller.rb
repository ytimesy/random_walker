class PreviewsController < ApplicationController
  def show
    url = params[:url].to_s
    loader = RandomWalker::PageLoader.new
    page = loader.load(url)

    render json: { url: page.url, label: page.label, html: page.html }
  rescue RandomWalker::LinkPicker::UnsafeURLError => e
    render json: {
      error: e.message,
      unsafe: true,
      reasons: e.reasons,
      blocked_url: e.candidate
    }, status: :unprocessable_entity
  rescue RandomWalker::PageLoader::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
