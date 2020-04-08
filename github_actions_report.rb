#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'rest-client'
require 'optparse'
require_relative 'octokit_utils'
require 'json'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: pr_work_done.rb [options]'
  opts.on('-f', '--file NAME', String, 'Module file list') { |v| options[:file] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
end

parser.parse!

options[:file] = 'modules.json' if options[:file].nil?

missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

util = OctokitUtils.new(options[:oauth])
parsed = util.load_module_list(options[:file])

result_hash = []
headers = { Authorization: "token #{options[:oauth]}" }

parsed.each do |m|
  begin
    limit = util.client.rate_limit!
    puts "Getting data from Github API for #{m['github_namespace']}/#{m['repo_name']}"
    if limit.remaining == 0
      #  sleep 60 #Sleep between requests to prevent Github API - 403 response
      sleep limit.resets_in
      puts 'Waiting for rate limit reset in Github API'
    end
    sleep 2 # Keep Github API happy
    url = "https://api.github.com/repos/#{m['github_namespace']}/#{m['repo_name']}/actions/workflows"
    result = RestClient.get(url, headers)

    data = JSON.parse(result.body)

    runs = {}

    data['workflows'].each do |wf|
      url = "https://api.github.com/repos/#{m['github_namespace']}/#{m['repo_name']}/actions/workflows/#{wf['id']}/runs"
      runs_json = RestClient.get(url, headers)
      runs[wf['name']] = JSON.parse(runs_json)
    end

    result_hash << {
      "url": "https://github.com/#{m['github_namespace']}/#{m['repo_name']}",
      "name": m['repo_name'],
      "workflows": data['workflows'],
      "runs": runs
    }
  rescue StandardError => e
    puts "#{m['repo_name']} - Error: #{e}"
    result_hash << {
      "url": "https://github.com/#{m['github_namespace']}/#{m['repo_name']}",
      "name": m['repo_name'],
      "workflows": 'Not available',
      "runs": 'Not available'
    }
  end
end

html = ERB.new(File.read('github_actions_report.html.erb')).result(binding)

File.open('GithubActionsReport.html', 'wb') do |f|
  f.puts(html)
end
