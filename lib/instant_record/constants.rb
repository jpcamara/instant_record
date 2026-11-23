# Plain values shared by the gem and the standalone compiler, which loads
# this file without Rails.
module InstantRecord
  DEFAULT_MOUNT_PATH = "/instant_record".freeze

  # Engine endpoints allow cross-origin reads and JSON writes so a separately
  # hosted compiled site or Vite dev server can reach Rails. Access control is
  # enforced per model via `sync_scope`, `syncable_to`, and `writable_by`.
  CORS_HEADERS = {
    "access-control-allow-origin" => "*",
    "access-control-allow-methods" => "GET, POST, OPTIONS",
    "access-control-allow-headers" => "content-type, last-event-id"
  }.freeze

  # Every timestamp crossing the wire carries microseconds, in both directions.
  # This used to differ per path — the change log and the outbox serialize
  # through ActiveSupport's JSON encoder, which stops at milliseconds, while the
  # bootstrap and records endpoints kept all six places — and the mismatch was
  # not cosmetic. It loses (created_at, id) keyset neighbours between history
  # pages, and it biases every last-write-wins comparison against whichever side
  # was rounded, which silently discarded writes on both.
  TIME_PRECISION = 6

  # Query marker that tells the service worker to pass one request to the
  # network instead of the local wasm runtime (see InstantRecord.server_url).
  NETWORK_MARKER = "instant_record_network=1".freeze
end
