require 'json'

When /^I request a work item as "([^"]*)"$/ do |downloader|
  post "/request",
       { "downloader" => downloader }.to_json,
       { "Content-Type" => "application/json" }
end

Then /^the response has status (\d+)$/ do |status|
  last_response.status.should == status.to_i
end

Then /^I receive a work item$/ do
  available_items.should include(last_response.body)
end
