require 'puppet'
require 'yaml'
require 'rubygems'
require 'json'
require 'rest-client'

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
    output = []
    self.logs.each do |log|
      output << log
    end

    @host = self.host

    send_logs(output,self.host)
    send_metrics(self.metrics,self.host)
    if self.status == 'failed'
      send_failed
    end
  end

  def send_logs(output)
    metadata = {
      :sourcetype => 'json_puppet-logs',
      :source => 'puppet',
      :host => @host,
      :index => CONFIG[:index]
    }
    event = output.to_json

    splunk_post(event, metadata)
  end

  def send_metrics(metrics)
    metadata = {
      :sourcetype => 'json_puppet-metrics',
      :source => 'puppet',
      :host => @host,
      :index => CONFIG[:index]
    }

    metrics.each { |metric,data|
      data.values.each { |val|
        name = "Puppet #{val[1]} #{metric}"
        if metric == 'time'
          unit = 'Seconds'
        else
          unit = 'Count'
        end
        value = val[2]
      }
    }
    splunk_post(event, metadata)
  end

  def send_failed
    metadata = {
          :sourcetype => 'json',
          :source => 'puppet',
          :host => @host,
          :index => CONFIG[:index]
    }

    event = {
      :failed => true,
      :start_time => "",
      :end_time => "",
      :elapsed_time => "",
      :exception => ""}.to_json

    splunk_post(event, metadata)
  end

  def splunk_post(event, metadata)
    api_params = metadata.collect{ |k,v| [k, v].join('=') }.join('&')
    url_params = URI.escape(api_params)
    endpoint_path = [API_ENDPOINT, url_params].join('?')

    request = RestClient::Resource.new(
      CONFIG[:splunk_url], :user => CONFIG[:user], :password => CONFIG[:password]
    )

    request[endpoint_path].post(event)
  end
end