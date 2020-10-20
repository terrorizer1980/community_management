# frozen_string_literal: true

require 'optparse'

def parse_options
  result = {}
  result[:oauth] = ENV['GITHUB_TOKEN'] if ENV['GITHUB_TOKEN']
  result[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
  result[:url] = 'https://puppetlabs.github.io/iac/modules.json'
  result[:modules] = 'https://puppetlabs.github.io/iac/modules.json'
  result[:tools]   = 'https://puppetlabs.github.io/iac/tools.json'

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
    opts.on('-u MANDATORY', '--url=MANDATORY', String, 'Link to json file for modules') { |v| result[:url] = v }
    opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| result[:oauth] = v }
    opts.on('-g', '--group GROUP', 'Repository group to operate on. One of [modules|tools]') do |v|
      case v.downcase
      when 'modules'
        result[:url] = result[:modules]
      when 'tools'
        result[:url] = result[:tools]
      else
        raise "Unsupported repository group. Please use one of [modules|tools]."
      end
    end
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
