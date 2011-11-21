require 'json'

When /^I request a work item as "([^"]*)"(?: from ip ([.0-9]+))?$/ do |downloader, ip|
  post "/request",
       { "downloader" => downloader }.to_json,
       { "Content-Type" => "application/json",
         "REMOTE_ADDR" => (ip || "127.0.0.1") }
end

When /^downloader "([^"]*)" marks item "([^"]*)" done with ([0-9]+) bytes$/ do |downloader, item, bytes|
  post "/done",
       { "downloader" => downloader,
         "user" => item,
         "bytes" => { "data"=>bytes.to_i } }.to_json,
       { "Content-Type" => "application/json" }
end

Then /^the response has status (\d+)$/ do |status|
  last_response.status.should == status.to_i
end

Then /^I receive a work item(?: "([^"]*)")?$/ do |item|
  available_items.should include(last_response.body) and
  (item.nil? or item.should == last_response.body.strip)
end

Then /^the tracker knows that "([^"]*)" is done$/ do |item|
  tracker.item_done?(item)
end

Then /^the tracker knows that "([^"]*)" is claimed by "([^"]*)"$/ do |item, downloader|
  tracker.item_claimed?(item) and
  tracker.item_claimant(item).should == downloader
end

Then /^the tracker knows that "([^"]*)" is not claimed$/ do |item|
  not tracker.item_claimed?(item)
end

Then /^the tracker knows that "([^"]*)" has downloaded ([0-9]+) items? and ([0-9]+) bytes$/ do |downloader, count, bytes|
  get "/stats.json"
  stats = JSON.parse(last_response.body)
  stats["downloader_count"][downloader].should == count.to_i and
  stats["downloader_bytes"][downloader].should == bytes.to_i
end

