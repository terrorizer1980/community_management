#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require_relative 'octokit_utils'
require_relative 'options'

options = parse_options

parsed = load_url(options)

util = OctokitUtils.new(options[:oauth])

open_prs = []

def does_array_have_pr(array, pr_number)
  found = false
  array.each do |entry|
    found = true if pr_number == entry.number
  end
  found
end

parsed.each do |_k, v|
  sleep(2)
  pr_information_cache = util.fetch_async((v['github']).to_s)
  # no comment from a puppet employee
  puppet_uncommented_pulls = util.fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
  # last comment mentions a puppet person
  mentioned_pulls = util.fetch_pull_requests_mention_member(pr_information_cache)

  # loop through open pr's and create a row that has all the pertinant info
  pr_information_cache.each do |pr|
    sleep(2)
    row = {}
    row[:repo] = v['title']
    row[:address] = pr[:pull][:url]
    row[:modified_workflow] = system("./get_pr_diff.sh #{row[:address]} | grep workflow")
    open_prs.push(row)
  end
end
File.open("wf_prs.csv", "w+") do |f|
  open_prs.each { |element| f.puts("#{element[:repo]},#{element[:address]},#{element[:modified_workflow]}") }
end
