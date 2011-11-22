Given /^the tracker has the work items$/ do |table|
  items = table.hashes.map { |t| t["item"] }
  post "/rescue-me", :items=>items.join("\n")
  available_items.push(*items)
end

Given /^ip ([.0-9]+) has been blocked$/ do |ip|
  tracker.block_ip(ip)
end

