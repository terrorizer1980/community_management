#!/usr/bin/env ruby
# frozen_string_literal: true

# https://docs.github.com/en/rest/reference/repos#update-branch-protection
# https://octokit.github.io/octokit.rb/Octokit/Client/Repositories.html#protect_branch-instance_method

require_relative 'octokit_utils'
require_relative 'options'

options = parse_options
util = OctokitUtils.new(options[:oauth])
client = util.client

contributor = 'SET HERE'

# parsed = load_url(options)
# parsed.each do |_k, v|
#   repo_name = (v['github']).to_s
['postgresql', 'stdlib', 'mysql', 'puppetdb'].each do |repo|
  # ['apache', 'apt', 'concat', 'inifile', 'postgresql', 'stdlib', 'xinetd'].each do |repo|
  repo_name = "puppetlabs/puppetlabs-#{repo}"
  begin
    client.add_collaborator(repo_name, contributor, permission: 'push')
    puts "added #{contributor} to #{repo_name}"
  rescue StandardError => e
    puts "failed to update #{repo_name}"
    puts e
  end
end
