#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'optparse'
require_relative 'octokit_utils'

class PuppetModule
  attr_accessor :name, :namespace, :tag_date, :commits, :downloads
  def initialize(name, namespace, tag_date, commits, downloads = 0)
    @name = name
    @namespace = namespace
    @tag_date = tag_date
    @commits = commits
    @downloads = downloads
  end
end

def get_number_of_prs_by_label(util, prs, label, mod)
  nr = 0
  prs.each do |pr_since_tag|
    label_of_pr = util.does_pr_have_label("#{mod['github_namespace']}/#{mod['repo_name']}", pr_since_tag[:pull][:number], label)

    nr += 1 if label_of_pr == true && !pr_since_tag[:pull][:merged_at].nil?
  end
  nr
end

puppet_modules = []
def number_of_downloads(module_name)
  uri = URI.parse("https://forgeapi.puppetlabs.com/v3/modules/#{module_name}")
  request =  Net::HTTP::Get.new(uri.path)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http| # pay attention to use_ssl if you need it
    http.request(request)
  end
  output = response.body
  parsed = JSON.parse(output)

  begin
    parsed['current_release']['downloads']
  rescue NoMethodError
    "Error number of downloads #{module_name}"
  end
end

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: release_planning.rb [options]'

  opts.on('-f', '--file NAME', String, 'Module file list') { |v| options[:file] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
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

options[:tag_regex] = '.*' if options[:tag_regex].nil?

util = OctokitUtils.new(options[:oauth])
parsed = util.load_module_list(options[:file])

repo_data = []

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

    latest_tag = util.fetch_tags("#{m['github_namespace']}/#{m['repo_name']}", options).first
    tag_ref = util.ref_from_tag(latest_tag)
    date_of_tag = util.date_of_ref("#{m['github_namespace']}/#{m['repo_name']}", tag_ref)
    commits_since_tag = util.commits_since_date_c("#{m['github_namespace']}/#{m['repo_name']}", date_of_tag)
    prs_since_tag = util.fetch_async("#{m['github_namespace']}/#{m['repo_name']}", options = { state: 'closed', sort: 'updated-desc' }, %i[statuses pull_request_commits issue_comments], attribute: 'closed_at', date: date_of_tag)

    no_maintenance_prs = get_number_of_prs_by_label(util, prs_since_tag, 'maintenance', m)
    no_feature_prs = get_number_of_prs_by_label(util, prs_since_tag, 'feature', m)
    no_bugfix_prs = get_number_of_prs_by_label(util, prs_since_tag, 'bugfix', m)
    no_incompatible_prs = get_number_of_prs_by_label(util, prs_since_tag, 'backwards-incompatible', m)

    repo_data << { 'repo' => "#{m['github_namespace']}/#{m['repo_name']}", 'date' => date_of_tag, 'commits' => commits_since_tag.size, 'downloads' => number_of_downloads(m['forge_name']), 'maintenance_prs' => no_maintenance_prs, 'feature_prs' => no_feature_prs, 'bugfix_prs' => no_bugfix_prs, 'incompatible_prs' => no_incompatible_prs }
    puppet_modules << PuppetModule.new(repo, "#{m['github_namespace']}/#{m['repo_name']}", date_of_tag, commits_since_tag)
  rescue StandardError
    puts "Unable to fetch tags for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end
sleep(2)

html = ERB.new(File.read('release_planning.html.erb')).result(binding)
File.open('ModulesRelease.html', 'wb') do |f|
  f.puts(html)
end
