Given /^the tracker has the work items$/ do |table|
  items = table.hashes.map { |t| t["item"] }
  available_items.push(*items)

  items.each { |item| $redis.sadd("todo", item) }
end

Given /^ip ([.0-9]+) has been blocked$/ do |ip|
  tracker.block_ip(ip)
end

