require 'spec_helper'

describe UploadTargets do
  let(:tracker) { stub(:redis => $redis, :prefix => 'test-project:') }
  let(:targets) { UploadTargets.new(tracker) }

  before do
    targets.clear
  end
  
  describe '#add' do
    it 'adds rsync://rsync.example.com/project/:downloader/ as-is' do
      targets.add('rsync://rsync.example.com/project/:downloader/')

      targets.all.first[:url].should == 'rsync://rsync.example.com/project/:downloader/'
    end

    it 'adds rsync://rsync.example.com/project/:downloader with a trailing slash' do
      targets.add('rsync://rsync.example.com/project/:downloader')

      targets.all.first[:url].should == 'rsync://rsync.example.com/project/:downloader/'
    end

    it 'adds http://http.example.com/project/:downloader/ as-is' do
      targets.add('http://http.example.com/project/:downloader/')

      targets.all.first[:url].should == 'http://http.example.com/project/:downloader/'
    end

    it 'adds http://http.example.com/project/:downloader with a trailing slash' do
      targets.add('http://http.example.com/project/:downloader')

      targets.all.first[:url].should == 'http://http.example.com/project/:downloader/'
    end
  end
end
