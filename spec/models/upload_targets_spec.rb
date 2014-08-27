require 'spec_helper'

describe UploadTargets do
  let(:tracker) { stub(:redis => $redis, :prefix => 'test-project:') }
  let(:targets) { UploadTargets.new(tracker) }

  before do
    targets.clear
  end

  describe '#add' do
    it 'adds rsync://rsync.example.com/project/:downloader/ as-is' do
      targets.add('rsync://rsync.example.com/project/:downloader/', 10)

      targets.all.first[:url].should == 'rsync://rsync.example.com/project/:downloader/'
    end

    it 'adds rsync://rsync.example.com/project/:downloader with a trailing slash' do
      targets.add('rsync://rsync.example.com/project/:downloader', 10)

      targets.all.first[:url].should == 'rsync://rsync.example.com/project/:downloader/'
    end

    it 'adds http://http.example.com/project/:downloader/ as-is' do
      targets.add('http://http.example.com/project/:downloader/', 10)

      targets.all.first[:url].should == 'http://http.example.com/project/:downloader/'
    end

    it 'adds http://http.example.com/project/:downloader with a trailing slash' do
      targets.add('http://http.example.com/project/:downloader', 10)

      targets.all.first[:url].should == 'http://http.example.com/project/:downloader/'
    end

    it 'does not add rsync://rsync.example.com/project/:downloader/ if it is present but inactive' do
      targets.add('rsync://rsync.example.com/project/:downloader/', 10)
      targets.deactivate('rsync://rsync.example.com/project/:downloader/')

      targets.add('rsync://rsync.example.com/project/:downloader/', 20)

      targets.all.length.should == 1
    end
  end

  describe '#rescore' do
    describe 'on unknown targets' do
      it 'returns false' do
        Timeout::timeout(1) do
          targets.rescore('foobarbaz', 20).should be_false
        end
      end
    end
  end

  describe '#random_target' do
    let(:t1) { 'rsync://big.example.com/module/:downloader/' }
    let(:t2) { 'rsync://small.example.com/module/:downloader/' }
    let(:t3) { 'rsync://alsosmall.example.com/module/:downloader/' }

    # Just in case you're wondering, there is absolutely no statistical meaning
    # behind these numbers.  They're just "acceptably" big and small.  Probably
    # overkill.
    let(:trials) { 500 }
    let(:tolerance) { 0.05 }
    let(:results) { [] }

    it 'returns the same target if there is only one target' do
      targets.add(t1, 1)

      trials.times { results << targets.random_target }

      results.length.should == trials
      results.all? { |r| r == t1 }
    end

    it 'weights by score' do
      targets.add(t1, 100)
      targets.add(t2, 10)

      # We expect to get t1 ~90% of the time and t2 ~10% of the time.
      trials.times { results << targets.random_target }

      t1s = results.select { |r| r == t1 }
      t2s = results.select { |r| r == t2 }
      (t1s.length.to_f / trials).should be_within(tolerance).of(0.9)
      (t2s.length.to_f / trials).should be_within(tolerance).of(0.1)
    end

    it 'permits multiple targets with the same score' do
      targets.add(t1, 100)
      targets.add(t2, 20)
      targets.add(t3, 20)

      # Expected results:
      #
      # t1: ~71%, t2: ~14%, t3: ~14%
      trials.times { results << targets.random_target }

      t1s = results.select { |r| r == t1 }
      t2s = results.select { |r| r == t2 }
      t3s = results.select { |r| r == t3 }
      (t1s.length.to_f / trials).should be_within(tolerance).of(0.71)
      (t2s.length.to_f / trials).should be_within(tolerance).of(0.14)
      (t3s.length.to_f / trials).should be_within(tolerance).of(0.14)
    end

    it 'does not select inactive targets' do
      targets.add(t1, 100)
      targets.add(t2, 10)
      targets.add(t3, 10)
      targets.deactivate(t2)

      trials.times { results << targets.random_target }

      t1s = results.select { |r| r == t1 }
      t2s = results.select { |r| r == t2 }
      t3s = results.select { |r| r == t3 }

      t2s.should be_empty
      (t1s.length.to_f / trials).should be_within(tolerance).of(0.9)
      (t3s.length.to_f / trials).should be_within(tolerance).of(0.1)
    end

    it 'selects reactivated targets' do
      targets.add(t1, 100)
      targets.add(t2, 20)
      targets.add(t3, 20)
      targets.deactivate(t2)
      targets.activate(t2)

      trials.times { results << targets.random_target }

      t1s = results.select { |r| r == t1 }
      t2s = results.select { |r| r == t2 }
      t3s = results.select { |r| r == t3 }
      (t1s.length.to_f / trials).should be_within(tolerance).of(0.71)
      (t2s.length.to_f / trials).should be_within(tolerance).of(0.14)
      (t3s.length.to_f / trials).should be_within(tolerance).of(0.14)
    end
  end
end
