require "spec_helper"

module UniversalTracker

  describe Tracker do
    before :each do
      @config = TrackerConfig.new
      @tracker = Tracker.new($redis, @config)
    end

    it "should keep a Redis connection" do
      tracker = Tracker.new($redis, @config)
      tracker.redis.should === $redis
    end

    it "should load the TrackerConfig" do
      $redis.set("tracker_config", '{"title":"foobar tracker"}')

      tracker = Tracker.new($redis)
      tracker.config.title.should == "foobar tracker"
    end

    it "should return a random item" do
      @tracker.add_items(["abc"])
      @tracker.random_item.should == "abc"
    end

    it "should block ips" do
      @tracker.block_ip("192.0.0.1")
      @tracker.block_ip("192.0.0.2", {"test"=>123})

      @tracker.ip_blocked?("192.0.0.1").should == true
      @tracker.ip_blocked?("192.0.0.2").should == true

      @tracker.ip_block_log.should == ['{"test":123}']
    end

    it "should be able to add items" do
      added = @tracker.add_items(["abc", "cde"])
      added.should == ["abc", "cde"]
    end

    it "should not add duplicate items" do
      @tracker.add_items(["abc", "cde"])

      added = @tracker.add_items(["abc", "cde", "fgh"])
      added.should == ["fgh"]
    end
  end

end

