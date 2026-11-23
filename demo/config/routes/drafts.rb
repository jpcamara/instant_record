# Drafts: one text, edited in two browsers that are both offline.
local_first do
  resources :drafts, only: [:index, :show, :create, :update]
end
