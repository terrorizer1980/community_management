# frozen_string_literal: true

require 'optparse'

def parse_options
  result = {}
  result[:oauth] = ENV['GITHUB_TOKEN'] if ENV['GITHUB_TOKEN']
  result[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
  result[:url] = 'https://puppetlabs.github.io/iac/modules.json'

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
    opts.on('-u MANDATORY', '--url=MANDATORY', String, 'Link to json file for modules') { |v| result[:url] = v }
    opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| result[:oauth] = v }
    yield opts, result if block_given?
  end

  parser.parse!

  missing = []
  missing << '-t' if result[:oauth].nil?
  unless missing.empty?
    puts "Missing options: #{missing.join(', ')}"
    puts parser
    exit
  end

  result
end

def load_url(options)
  uri = URI.parse(options[:url])
  response = Net::HTTP.get_response(uri)
  output = response.body
  JSON.parse(output)
end
