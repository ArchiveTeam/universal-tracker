require "spec_helper"

module UniversalTracker

  describe Tracker do
    before :each do
      @config = TrackerConfig.new('test-project')
      @manager = TrackerManager.new($redis)
      @tracker = Tracker.new($redis, @manager, @config)
    end

    it "should keep a Redis connection" do
      tracker = Tracker.new($redis, @manager, @config)
      tracker.redis.should === $redis
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
      @tracker.blocked?(["192.0.0.1"])
    end

    it "should block downloaders" do
      @tracker.block_downloader("someone")
      @tracker.downloader_blocked?("someone").should == true
      @tracker.blocked?(["someone"])
    end

    it "should refuse funky downloader nicks" do
      App.valid_downloader?("a").should == false
      App.valid_downloader?("aaa>/dev/null").should == false
      App.valid_downloader?("aaa\u1F31D").should == false
      App.valid_downloader?("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").should == false
      App.valid_downloader?("hello").should == true
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

    describe "#release_item" do
      context "when there is a claimed item" do
        before do
          @tracker.add_items(["abc"])
          @tracker.request_item("127.0.0.1", "downloader")
        end

        it "should return that to the queue" do
          answer = @tracker.release_item("abc")
          answer.should == true
          @tracker.item_todo?("abc").should == true
          @tracker.item_claimed?("abc").should == false
          @tracker.item_claimant("abc").should == nil
        end
      end

      context "when there is no claimed item" do
        it "should not return that item to the queue" do
          answer = @tracker.release_item("abc")
          answer.should == false
          @tracker.item_todo?("abc").should == false
        end
      end
    end

    describe "#release_stale" do
      before do
        @tracker.add_items(["abc","def"])
        @tracker.request_item("127.0.0.1", "downloader")
        @tracker.request_item("127.0.0.1", "downloader")
        $redis.zadd("#{@tracker.prefix}out", Time.now.to_i - 24 * 60 * 60, "abc")
      end

      it "should return the stale claims to the queue" do
        answer = @tracker.release_stale(Time.now - 12 * 60 * 60)
        answer.should == [ "abc" ]
        @tracker.item_todo?("abc").should == true
        @tracker.item_claimed?("def").should == true
      end
    end

    describe "#release_by_downloader" do
      before do
        @tracker.add_items(["abc"])
        @tracker.request_item("127.0.0.1", "downloader_a")
        @tracker.add_items(["def"])
        @tracker.request_item("127.0.0.1", "downloader_b")
      end

      it "should return the items claimed by the downloader" do
        answer = @tracker.release_by_downloader("downloader_a")
        answer.should == [ "abc" ]
        @tracker.item_todo?("abc").should == true
        @tracker.item_claimed?("def").should == true
      end
    end

    describe "#mark_item_done" do
      before do
        @tracker.add_items(["abc", "def", "ghi"])
      end

      it "should update the statistics" do
        @tracker.mark_item_done("downloader", "abc", { "data"=>123 }, {})
        @tracker.stats["downloader_bytes"]["downloader"].should == 123
        @tracker.stats["downloader_count"]["downloader"].should == 1
        @tracker.stats["domain_bytes"]["data"].should == 123

        @tracker.mark_item_done("downloader", "def", { "data"=>123 }, {})
        @tracker.stats["downloader_bytes"]["downloader"].should == 123+123
        @tracker.stats["downloader_count"]["downloader"].should == 2
        @tracker.stats["domain_bytes"]["data"].should == 123+123
      end

      it "should not count resubmitted items" do
        10.times do
          @tracker.mark_item_done("downloader", "abc", { "data"=>123 }, {})
        end

        @tracker.stats["downloader_bytes"]["downloader"].should == 123
        @tracker.stats["downloader_count"]["downloader"].should == 1
        @tracker.stats["domain_bytes"]["data"].should == 123
      end

      it "should send a pubsub message" do
        @tracker.redis.should_receive(:publish) do |channel, message|
          channel.should == @manager.config.redis_pubsub_channel
          message.should be_a(String)
          msg = JSON.parse(message)
          msg["log_channel"].should == @tracker.config.live_log_channel
          msg["downloader"].should == "downloader"
          msg["item"].should == "abc"
          msg["is_duplicate"].should == false
        end

        @tracker.mark_item_done("downloader", "abc", { "data"=>123 }, {})
      end

      it "should send a different pubsub message for duplicates" do
        @tracker.mark_item_done("downloader", "abc", { "data"=>123 }, {})

        @tracker.redis.should_receive(:publish) do |channel, message|
          msg = JSON.parse(message)
          msg["is_duplicate"].should == true
        end

        @tracker.mark_item_done("downloader", "abc", { "data"=>123 }, {})
      end

      context "when there is a todo item" do
        it "should mark the item done" do
          @tracker.mark_item_done("downloader", "abc", { "data"=>123 }, {})
          @tracker.item_todo?("abc").should == false
          @tracker.item_claimed?("abc").should == false
          @tracker.item_claimant("abc").should == nil
          @tracker.item_done?("abc").should == true
        end
      end

      context "when there is a claimed item" do
        before do
          @tracker.request_item("127.0.0.1", "downloader")
        end

        it "should mark the item done" do
          @tracker.mark_item_done("downloader", "abc", { "data"=>123 }, {})
          @tracker.item_todo?("abc").should == false
          @tracker.item_claimed?("abc").should == false
          @tracker.item_claimant("abc").should == nil
          @tracker.item_done?("abc").should == true
        end
      end

      context "when there is no such item" do
        it "should do nothing" do
          @tracker.mark_item_done("downloader", "def", { "data"=>123 }, {})
          @tracker.item_done?("abc").should == false
        end
      end
    end
  end

end

