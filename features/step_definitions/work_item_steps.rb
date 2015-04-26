require 'json'

When /^I request a work item as "([^"]*)"(?: from ip ([.0-9]+))?$/ do |downloader, ip|
  post "/test-project/request",
       { "downloader" => downloader }.to_json,
       { "Content-Type" => "application/json",
         "REMOTE_ADDR" => (ip || "127.0.0.1") }
end

When /^downloader "([^"]*)" marks item "([^"]*)" done with ([0-9]+) bytes$/ do |downloader, item, bytes|
  post "/test-project/done",
       { "downloader" => downloader,
         "item" => item,
         "bytes" => { "data"=>bytes.to_i } }.to_json,
       { "Content-Type" => "application/json" }
end

When /^downloader max budget is (\d+)$/ do |budget|
  post "/test-project/admin/limits", :max_budget => budget
  last_response.status.should == 302
end

Then /^the response has status (\d+)$/ do |status|
  last_response.status.should == status.to_i
end

Then /^I receive a work item(?: "([^"]*)")?$/ do |item|
  available_items.should include(last_response.body)
  (item.nil? or item.should == last_response.body.strip)
end

Then /^the tracker knows that "([^"]*)" is done$/ do |item|
  get "/test-project/items/#{ item }.json"
  JSON.parse(last_response.body)["status"].should == "done"
end

Then /^the tracker knows that "([^"]*)" is claimed by "([^"]*)"$/ do |item, downloader|
  get "/test-project/items/#{ item }.json"
  data = JSON.parse(last_response.body)
  data["status"].should == "out"
  data["downloader"].should == downloader
end

Then /^the tracker knows that "([^"]*)" is not claimed$/ do |item|
  get "/test-project/items/#{ item }.json"
  JSON.parse(last_response.body)["status"].should_not == "done"
end

Then /^the tracker knows that "([^"]*)" has downloaded ([0-9]+) items? and ([0-9]+) bytes$/ do |downloader, count, bytes|
  get "/test-project/stats.json"
  text = Zlib::GzipReader.new(StringIO.new(last_response.body)).read
  stats = JSON.parse(text)
  stats["downloader_count"][downloader].should == count.to_i
  stats["downloader_bytes"][downloader].should == bytes.to_i
end

