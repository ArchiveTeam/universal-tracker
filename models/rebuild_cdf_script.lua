-- active looks like this:
--
-- ['foo', 10, 'bar', 20]
local active = redis.call('zrange', KEYS[1], 0, -1, 'withscores')

-- step 1: normalize scores from 0.0 to 1.0
local scores = {}
local targets = {}
local accum = 0

for i = 1, #active, 2 do
  local score = active[i + 1]
  accum = accum + score

  table.insert(targets, active[i])
  table.insert(scores, accum)
end

for i, score in ipairs(scores) do
  scores[i] = scores[i] / accum
end

-- step 2: rebuild the cdf
redis.call('del', KEYS[2])

for i, target in ipairs(targets) do
  local score = scores[i]

  redis.call('zadd', KEYS[2], score, target)
end

-- vim: set ts=2 sw=2 et tw=78:
