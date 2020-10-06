#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'octokit_utils'
require_relative 'options'

def primary_remote
  ['upstream', 'origin'].map do |name|
    get_remote(name)
  end.compact.first
end

def get_remote(name)
  require 'rugged'
  remote = Rugged::Repository.new('.').remotes[name] rescue nil
  parts  = remote.url.match(/(\w+\/[\w-]+)(?:\.git)?$/) if remote
  parts[1] if parts
end

options = parse_options do |opts, result|
  opts.on('-f', '--fix-topics', 'Add the missing topics to repo') { result[:fix_topics] = true }
  opts.on('-d', '--delete-topics', 'Delete unwanted topics from repo') { result[:delete_topics] = true }

  opts.on('--repo [REPO]', 'Pass a repository name, defaults to the current upstream.') do |v|
    result[:remote] = v || primary_remote
    raise 'Could not guess primary remote. Try using --remote instead.' unless result[:remote]
  end

  opts.on('--remote REMOTE', 'Name of a remote to work on.') do |v|
    result[:remote] = get_remote(v)
    raise "No url set for remote #{v}" unless result[:remote]
  end
end

if options[:remote]
  parsed = { options[:remote] => { 'github' => options[:remote] } }
else
  parsed = load_url(options)
end

util = OctokitUtils.new(options[:oauth])

wanted_topics = [ 'hacktoberfest' ]

puts "Checking for the following topics: #{wanted_topics}"

parsed.each do |_k, v|
  repo_name = (v['github']).to_s

  topics  = util.client.topics(repo_name)[:names]
  extra   = topics - wanted_topics
  missing = wanted_topics - topics
  final   = topics

  if options[:delete_topics]
    final -= extra
  end
  if options[:fix_topics]
    final += missing
  end

  puts "Delete: #{repo_name}, #{extra}"
  puts "Create: #{repo_name}, #{missing}"
  puts "Topics: #{repo_name}, #{final}"

  next unless options.include?(:delete_topics) or options.include?(:fix_topics)
  util.client.replace_all_topics(repo_name, final)
end
