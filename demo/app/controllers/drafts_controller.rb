# The page's script holds the text as a Yjs document. It saves the document's
# whole state here, and reads it back when the record changes.
class DraftsController < ApplicationController
  extend InstantRecord::RuntimeScoped

  browser_only do
    skip_forgery_protection   # no session secrets in the local runtime
  end

  def index
    @drafts = Draft.order(created_at: :desc)
  end

  # With ?fragment=1, only the stored state, for the page's script to merge.
  def show
    @draft = Draft.find(params[:id])
    render partial: "state", layout: false if params[:fragment]
  end

  def create
    draft = Draft.create!(draft_params)
    redirect_to draft_path(draft)
  end

  # Answers with the stored state, so the page reads what was saved.
  def update
    @draft = Draft.find(params[:id])
    @draft.update!(draft_params)
    render partial: "state", layout: false
  end

  private

  def draft_params
    params.require(:draft).permit(:title, :title_ydoc, :body, :body_ydoc)
  end
end
