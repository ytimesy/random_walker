class SearchWalksController < ApplicationController
  def show
    term = params[:q].to_s
    walker = RandomWalker::SearchWalker.new
    link = walker.next_link(term)

    render json: { url: link.url, label: link.label, html: link.html, query: term }
  rescue RandomWalker::LinkPicker::UnsafeURLError => e
    render json: {
      error: e.message,
      unsafe: true,
      reasons: e.reasons,
      blocked_url: e.candidate,
      query: term
    }, status: :unprocessable_entity
  rescue RandomWalker::SearchWalker::Error => e
    render json: { error: e.message, query: term }, status: :unprocessable_entity
  end
end
