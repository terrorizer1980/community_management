#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'optparse'
require_relative 'octokit_utils'
require 'puppet_forge'

PuppetForge.user_agent = "IAC Community Management/1.0.0"

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] || ENV['GITHUB_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on('-t', '--oauth-token TOKEN', 'GitHub OAuth token. Required.') { |v| options[:oauth] = v }
end

parser.parse!

missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

util = OctokitUtils.new(options[:oauth])
@client = util.client

YEAR_OLD  = (Time.now - (60*60*24*365))
MONTH_OLD = (Time.now - (60*60*24*30))
WEEK_OLD  = (Time.now - (60*60*24*7))


def repo_name_from_url(url)
  return unless url.is_a? String

  # extracts <user name>/<repo name> and strips off optional ".git" string
  matches = url.match(/github\.com[\/:]([\w\/-]+)(?:\.git)?$/)

  matches[1] if matches
end

def repo_info(repo)
  begin
    info = @client.repository(repo)
  rescue Octokit::NotFound
    return
  end

  info.issues, info.pulls = @client.list_issues(repo).partition { |issue| issue.has_key? :pull_request }
  info.all_commits   = @client.commits(repo)
  info.fresh_commits = @client.commits_since(repo, Date.today - 30*6) # commits in the last 6 months

  info
end

def eligible?(mod)
  # don't even bother checking the repo if the current release is newer than 6 months
  return if DateTime.parse(mod.current_release.created_at) > (Date.today - 30*6)

  repo = repo_info(repo_name_from_url(mod.current_release.metadata[:source]))

  if repo.nil?
    $stderr.puts ("Warning: deleted module repository - #{mod.slug}")
    return
  end

  if repo.archived
    $stderr.puts ("Warning: archived module repository - #{mod.slug}")
    return true
  end

  # conditions which make this module *ineligible* for adoption
  return if repo.created_at > YEAR_OLD            # less than a year old
  return if repo.updated_at > WEEK_OLD            # the repo config has been updated in the last week
  return if repo.fresh_commits.size > 2           # has had more than two commits in the last 6 months
  return if repo.all_commits.first.commit.committer.date > MONTH_OLD # has had any commits in the last month

  unless repo.pulls.empty?
    return if repo.pulls.last.created_at > YEAR_OLD # oldest PR is less than a year old
  end

  # all eligibiliity checks complete
  true
end

modules = PuppetForge::Module.where(
             :owner           => 'puppetlabs', # rubocop:disable Layout/FirstArgumentIndentation
             :hide_deprecated => true,
             :module_groups   => 'base pe_only',
          )

raise "No modules found for #{namespace}." if modules.total.zero?


adoption_list = []
modules.unpaginated.each do |mod|
  next unless mod.endorsement.nil?
  next unless eligible?(mod)

  adoption_list << {
    :name           => mod.name,
    :owner          => mod.owner.username,
    :slug           => mod.slug,
    :summary        => mod.current_release.metadata[:summary],
    :gravatar_id    => mod.owner.gravatar_id,
    :version        => mod.current_release.version,
    :updated_at     => mod.updated_at,
    :downloads      => mod.downloads,
    :feedback_score => mod.feedback_score,
    :homepage_url   => mod.homepage_url,
  }
end

File.write('adoptable_modules.html', ERB.new(File.read('adoptable_modules.html.erb')).result(binding))
File.write('adoptable_modules.json', JSON.pretty_generate(adoption_list))


