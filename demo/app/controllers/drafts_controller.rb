# The form posts the draft's Yjs document with its fields, and the page that
# answers holds the document as saved.
class DraftsController < ApplicationController
  extend InstantRecord::RuntimeScoped

  browser_only do
    skip_forgery_protection   # no session secrets in the local runtime
  end

  def index
    @drafts = Draft.order(created_at: :desc)
  end

  def show
    @draft = Draft.find(params[:id])
  end

  def create
    draft = Draft.create!(draft_params)
    redirect_to draft_path(draft)
  end

  def update
    draft = Draft.find(params[:id])
    draft.update!(draft_params)
    redirect_to draft_path(draft)
  end

  private

  def draft_params
    params.require(:draft).permit(:title, :body, :fields_ydoc)
  end
end
