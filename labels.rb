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
  parts = `git remote get-url #{name} 2>/dev/null`.match(/(\w+\/[\w-]+)(?:\.git)?$/)
  parts[1] if parts
end

options = parse_options do |opts, result|
  opts.on('-f', '--fix-labels', 'Add the missing labels to repo') { result[:fix_labels] = true }
  opts.on('-d', '--delete-labels', 'Delete unwanted labels from repo') { result[:delete_labels] = true }

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

wanted_labels = [{ name: 'needs-squash', color: 'bfe5bf' }, { name: 'needs-rebase', color: '3880ff' }, { name: 'needs-tests', color: 'ff8091' }, { name: 'needs-docs', color: '149380' }, { name: 'bugfix', color: '00d87b' }, { name: 'feature', color: '222222' }, { name: 'tests-fail', color: 'e11d21' }, { name: 'backwards-incompatible', color: 'd63700' }, { name: 'maintenance', color: 'ffd86e' }]

label_names = []
wanted_labels.each do |wanted_label|
  label_names.push(wanted_label[:name])
end
puts "Checking for the following labels: #{label_names}"

parsed.each do |_k, v|
  repo_name = (v['github']).to_s
  missing_labels = util.fetch_repo_missing_labels(repo_name, wanted_labels)
  incorrect_labels = util.fetch_repo_incorrect_labels(repo_name, wanted_labels)
  extra_labels = util.fetch_repo_extra_labels(repo_name, wanted_labels)
  puts "Delete: #{repo_name}, #{extra_labels}"
  puts "Create: #{repo_name}, #{missing_labels}"
  puts "Fix: #{repo_name}, #{incorrect_labels}"

  if options[:delete_labels]
    util.delete_repo_labels(repo_name, extra_labels) unless extra_labels.empty?
  end
  next unless options[:fix_labels]

  util.update_repo_labels(repo_name, incorrect_labels) unless incorrect_labels.empty?
  util.add_repo_labels(repo_name, missing_labels) unless missing_labels.empty?
end
