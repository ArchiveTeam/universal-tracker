Given /^the tracker has the work items$/ do |table|
  post "/global-admin/trackers", :slug=>"test-project"
  items = table.hashes.map { |t| t["item"] }
  post "/test-project/rescue-me", :items=>items.join("\n")
  available_items.push(*items)
end

Given /^ip ([.0-9]+) has been blocked$/ do |ip|
  tracker = $tracker_manager.tracker_for_slug("test-project")
  tracker.block_ip(ip)
end

