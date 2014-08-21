require 'uri'

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
    redis.zrangebyscore(cdf_key, rand, '+inf', limit: [0, 1]).first
  end

  def active_with_scores
    redis.zrange(active_upload_targets_key, 0, -1, with_scores: true) || []
  end

  def active
    active_with_scores.map(&:first)
  end

  def inactive_with_scores
    redis.zrange(inactive_upload_targets_key, 0, -1, with_scores: true) || []
  end

  def inactive
    inactive_with_scores.map(&:first)
  end

  def activate(url)
    redis.eval(MOVE_SCRIPT,
               [inactive_upload_targets_key, active_upload_targets_key],
               [url])
    rebuild_cdf
  end

  def deactivate(url)
    redis.eval(MOVE_SCRIPT,
               [active_upload_targets_key, inactive_upload_targets_key],
               [url])
    rebuild_cdf
  end

  def all
    active = active_with_scores.map { |t, s| { url: t, score: s, active: true } }
    inactive = inactive_with_scores.map { |t, s| { url: t, score: s, active: false } }

    (active + inactive).sort_by { |target| target[:url] }
  end

  def add(url, score, key = active_upload_targets_key)
    # If the URL and score don't meet requirements, bail.
    return unless target_ok?(url, score)

    conformed_url = conform(url)

    # If the target URL is in a different key set than the set we want to
    # modify, bail.
    if set_key = set_for_url(conformed_url)
      return if set_key != key
    end

    # Add or re-score the URL.
    redis.zadd(key, score, conformed_url)
    rebuild_cdf
  end

  def rescore(url, score)
    return unless target_ok?(url, score)

    loop do
      if redis.zscore(active_upload_targets_key, url)
        redis.watch(active_upload_targets_key)
        if redis.multi { add(url, score, active_upload_targets_key) }
          return true
        end
      elsif redis.zscore(inactive_upload_targets_key, url)
        redis.watch(inactive_upload_targets_key)
        if redis.multi { add(url, score, inactive_upload_targets_key) }
          return true
        end
      else
        return false
      end
    end
  end

  def remove(url)
    redis.multi do
      redis.zrem(active_upload_targets_key, url)
      redis.zrem(inactive_upload_targets_key, url)
    end

    rebuild_cdf
  end

  def clear
    redis.multi do
      redis.del(active_upload_targets_key)
      redis.del(inactive_upload_targets_key)
      redis.del(cdf_key)
    end
  end

  private

  def conform(url)
    if !URI(url).path.end_with?('/')
      url + '/'
    else
      url
    end
  end

  def set_for_url(url)
    redis.eval(SET_FOR_KEY_SCRIPT,
               [active_upload_targets_key, inactive_upload_targets_key],
               [url])
  end

  def rebuild_cdf
    redis.eval(REBUILD_CDF_SCRIPT, [active_upload_targets_key, cdf_key])
  end

  def active_upload_targets_key
    "#{tracker.prefix}upload_target"
  end

  def inactive_upload_targets_key
    "#{tracker.prefix}inactive_upload_target"
  end

  def cdf_key
    "#{tracker.prefix}upload_target_cdf"
  end

  def target_ok?(url, score)
    !url.empty? && score > 0
  end

  REBUILD_CDF_SCRIPT = File.read(File.expand_path('../rebuild_cdf_script.lua', __FILE__)).freeze

  SET_FOR_KEY_SCRIPT = %q{
    local candidate = ARGV[1]

    for i, key in ipairs(KEYS) do
      if redis.call('zscore', key, candidate) then
        return key
      end
    end
  }

  MOVE_SCRIPT = %q{
    local score = redis.call('zscore', KEYS[1], ARGV[1])

    if score ~= nil then
      redis.call('zrem', KEYS[1], ARGV[1])
      redis.call('zadd', KEYS[2], score, ARGV[1])
    end
  }.freeze
end
