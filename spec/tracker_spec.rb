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

    describe "#add_item" do
      it "should add items" do
        added = @tracker.add_items(["abc", "cde"])
        added.should == ["abc", "cde"]
      end

      it "should not add duplicate items" do
        @tracker.add_items(["abc", "cde"])

        added = @tracker.add_items(["abc", "cde", "fgh"])
        added.should == ["fgh"]
      end

      it "should not add items that are already claimed" do
        @tracker.add_items(["abc"])
        @tracker.request_item("", "")
        
        added = @tracker.add_items(["abc"])
        added.should == []
      end

      it "should not add items that are already done" do
        @tracker.add_items(["abc"])
        @tracker.mark_item_done("dld", "abc", {}, {})
        
        added = @tracker.add_items(["abc"])
        added.should == []
      end
    end

    describe "#request_item" do
      context "when there is an item" do
        before { @tracker.add_items(["abc"]) }

        it "should give you an item and mark it claimed" do
          item = @tracker.request_item("127.0.0.1", "downloader")
          item.should == "abc"

          @tracker.item_todo?("abc").should == false
          @tracker.item_claimed?("abc").should == true
          @tracker.item_claimant("abc").should == "downloader"
        end
      end

      context "when there is no item" do
        it "should give you nil" do
          item = @tracker.request_item("127.0.0.1", "downloader")
          item.should == nil
        end
      end

      context "when there is an item specifically for you" do
        before do
          @tracker.add_items(["abc"])
          @tracker.add_items_for_downloader!("downloader", ["DEF"])
        end

        it "should give you that item and mark it claimed" do
          item = @tracker.request_item("127.0.0.1", "downloader")
          item.should == "DEF"

          @tracker.item_todo?("DEF").should == false
          @tracker.item_claimed?("DEF").should == true
          @tracker.item_claimant("DEF").should == "downloader"
        end
      end
    end
  end

end

