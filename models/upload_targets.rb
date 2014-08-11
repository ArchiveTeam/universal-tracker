##
# Stores a set of upload targets for a tracker and provides methods for
# weighting, activating, and deactivating them.
#
# An upload target is a URL.
class UploadTargets
  attr_reader :redis
  attr_reader :tracker

  def initialize(tracker)
    @tracker = tracker
    @redis = tracker.redis
  end

  def random_target
    redis.srandmember(active_upload_targets_key)
  end

  def active
    redis.smembers(active_upload_targets_key) || []
  end

  def inactive
    redis.smembers(inactive_upload_targets_key) || []
  end

  def activate(url)
    redis.smove(inactive_upload_targets_key, active_upload_targets_key, url)
  end

  def deactivate(url)
    redis.smove(active_upload_targets_key, inactive_upload_targets_key, url)
  end

  def all
    (active.map{|t|{:url=>t, :active=>true}} +
     inactive.map{|t|{:url=>t, :active=>false}}).sort_by do |target|
      target[:url]
    end
  end

  def add(url)
    activate(url) or redis.sadd(active_upload_targets_key, url)
  end

  def remove(url)
    redis.srem(active_upload_targets_key, url)
    redis.srem(inactive_upload_targets_key, url)
  end

  private

  def active_upload_targets_key
    "#{tracker.prefix}upload_target"
  end

  def inactive_upload_targets_key
    "#{tracker.prefix}inactive_upload_target"
  end
end
