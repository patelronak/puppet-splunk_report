require 'puppet'
require 'yaml'
require 'rubygems'
require 'json'
require 'rest-client'
require 'uri'

unless Puppet.version >= '2.6.5'
  fail "This report processor requires Puppet version 2.6.5 or later"
end

Puppet::Reports.register_report(:splunk) do

  configfile = File.join([File.dirname(Puppet.settings[:config]), "splunk.yaml"])
  raise(Puppet::ParseError, "Splunk report config file #{configfile} not readable") unless File.exist?(configfile)
  CONFIG = YAML.load_file(configfile)
  API_ENDPOINT = 'services/receivers/simple'

  desc <<-DESC
  Send notification of reports to Splunk.
  DESC

  def process
    output = self.logs.inject([]) do |a, log|
      a.concat(["#{log.source}: #{log.message}"])
    end

    @host = self.host
    self.status == 'failed' ? @failed = true : @failed = false
    @start_time = self.logs.first.time
    @elapsed_time = metrics["time"]["total"]

    if metrics["resources"]
      @resource_count = {
        :failed      => metrics["resources"]["failed"],
        :changed     => metrics["resources"]["changed"],
        :out_of_sync => metrics["resources"]["out_of_sync"],
        :total       => metrics["resources"]["total"]
      }
    else
      @resource_count = nil
    end

    cl_app  = "none"
    cl_tier = "none"
    cl_env  = "none"

    node_facts = YAML.load_file("#{Puppet[:vardir]}/yaml/facts/#{self.host}.yaml")
    node_facts.values.each do |key, value|
      if ( key == "cl_app" )
        cl_app = value
      end
      if ( key == "cl_tier" )
        cl_tier = value
      end
      if ( key == "cl_env" )
        cl_env = value
      end
    end
    @myfacts = {
      :cl_app  => cl_app,
      :cl_tier => cl_tier,
      :cl_env  => cl_env,
    }

    send_event(output)
  end

  def send_event(output)
    metadata = {
      :sourcetype => 'json',
      :source     => 'puppet',
      :host       => @host,
      :index      => CONFIG[:index]
    }

    event = {
      :failed         => @failed,
      :start_time     => @start_time,
      :end_time       => Time.now,
      :elapsed_time   => @elapsed_time,
      :log            => output,
      :resource_count => @resource_count,
      :facts          => @myfacts
    }

    marshalled_event = event.to_json

    splunk_post(marshalled_event, metadata)
  end

  def splunk_post(event, metadata)
    api_params    = metadata.collect{ |k,v| [k, v].join('=') }.join('&')
    url_params    = URI.escape(api_params)
    endpoint_path = [API_ENDPOINT, url_params].join('?')

    request       = RestClient::Resource.new(
      CONFIG[:server], :user => CONFIG[:user], :password => CONFIG[:password]
    )

    request[endpoint_path].post(event)
  end
end
