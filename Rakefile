require 'cucumber/rake/task'

namespace :cucumber do
  desc 'Run features that should pass'
  Cucumber::Rake::Task.new(:ok) do |t|
    t.profile = :default
  end

  desc 'Run features that need work'
  Cucumber::Rake::Task.new(:wip) do |t|
    t.profile = :wip
  end

  desc 'Run all features'
  task :all => ['cucumber:ok', 'cucumber:wip']
end

task :default => 'cucumber:all'
