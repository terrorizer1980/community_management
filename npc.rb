#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: npc.rb [options]'
  opts.on('-u MANDATORY', '--url=MANDATORY', String, 'Link to json file for modules') { |v| options[:url] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-m', '--merge-conflicts', 'Comment / label PRs that have merge conflicts') { options[:merge_conflicts] = true }
  opts.on('-N', '--no-op', 'No-op, dont actually edit the PRs') { options[:no_op] = true }
end

parser.parse!

options[:url] = 'https://puppetlabs.github.io/iac/modules.json' if options[:url].nil?
missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

uri = URI.parse(options[:url])
response = Net::HTTP.get_response(uri)
output = response.body
parsed = JSON.parse(output)

util = OctokitUtils.new(options[:oauth])

if options[:no_op]
  puts 'RUNNING IN NO-OP MODE'
else
  puts 'MAKING CHANGES TO YOUR REPOS'
end

parsed.each do |_k, v|
  next unless options[:merge_conflicts]

  prs = util.fetch_pull_requests((v['github']).to_s)
  prs.each do |pr|
    # do we already have a label ?
    pr_merges = util.does_pr_merge((v['github']).to_s, pr.number)
    puts pr_merges
    pr_has_label = util.does_pr_have_label((v['github']).to_s, pr.number, 'needs-rebase')
    if pr_merges
      # pr merges
      # we have a label. should we remove the label if it is mergable
      if pr_has_label
        puts "#{m['github_namespace']} #{pr.number} removing label"
        util.remove_label_from_pr((v['github']).to_s, pr.number, 'needs-rebase') unless options[:no_op]
      end

      # pr does not merge
    elsif pr_has_label
      # has label
      puts "#{v['github']} #{pr.number} already labeled"
    else
      # pr does not have a label
      puts "#{v['github']} #{pr.number} adding comment and label"
      unless options[:no_op]
        # do comment
        util.add_comment_to_pr((v['github']).to_s, pr.number, "Thanks @#{pr.user.login} for your work, but can't be merged as it has conflicts. Please rebase them on the current master, fix the conflicts and repush here. https://git-scm.com/book/en/v2/Git-Branching-Rebasing")
        # do label
        util.add_label_to_pr((v['github']).to_s, pr.number, 'needs-rebase')
      end
    end
  end
end
