#!/usr/bin/env ruby
#
# etcd-watcher.rb
#

require 'etcd'
require 'optparse'
require 'logger'

@logger = Logger.new(STDOUT)
@logger.level = Logger::INFO

args = ARGV.dup
options = {}
optparse = OptionParser.new do |o|
  o.banner = "Usage: etcd-watcher.rb [options]"

  o.on('-c', '--command COMMAND', 'Command to execute.') do |c|
    options[:cmd] = c
  end

  o.on('-h', '--heartbeat [SECONDS]',
       'Interval to heartbeat etcd leader. Default: 10 seconds') do |h|
    options[:hb] = h
  end

  o.on('-k', '--key FULL_KEY_PATH', 'Full path to key to heartbeat.') do |k|
    options[:key] = k
  end

  o.on('-r', '--retry [RETRY_INTERVAL]',
       'How many seconds to wait before retrying if etcd is unavailable') do |r|
    options[:retry_interval] = r
  end

  o.on('-u', '--uris [http://server1:4001,http://server2:4001]', Array,
       'List etcd server URIs. Default to http://localhost:4001.') do |u|
    options[:uri] = u
  end

  o.on('-v', '--[no-]verbose', 'Run in verbose mode: log at debug') do |v|
    @logger.level = Logger::DEBUG if v
  end

  o.on_tail("-h", "--help", "Show this message") { puts o; exit }

  # TODO: Parameters for TTL and how often to heartbeat
end

optparse.parse!(args)

retry_interval = options.has_key?(:retry_interval) ? options[:retry_interval] : 30

@etcd = {}
@etcd[:uris] = options.has_key?(:uri) ? options[:uri] : ['http://127.0.0.1:4001']
@etcd[:heartbeat_freq] = options.has_key?(:hb) ? options[:hb].to_f : 10.0

def etcd_connect
  @logger.debug "Connecting etcd client with options #{@etcd.inspect}"
  @client = Etcd::Client.new(@etcd)
  @client.connect
end

@logger.debug "Spawning process #{options[:cmd]}"
process = Process.spawn(options[:cmd])
@pid = process.to_i

etcd_connect

trap(17) {
  begin
    @client.delete(options[:key])
    Process.wait
    status = $?.exitstatus.nil ? "unknown" : $?.exitstatus
    process = $?.pid.nil? ? "unknown" : $?.pid
    exit status
  ensure
    exit 0
  end
}

trap(2) {
  begin
    Process.kill(2, @pid)
    Process.wait
    if $?.exitstatus.nil? then exit 1 else exit $?.exitstatus end
  ensure
    exit 1
  end
}

trap(15) {
  begin
    @client.delete(options[:key])
    Process.kill(15, @pid)
    Process.wait
    if $?.exitstatus.nil? then exit 0 else exit $?.exitstatus end
  ensure
    exit 0
  end
}


begin
  loop do
    @client.set(options[:key], "alive", {ttl: 30})
    sleep 15
  end
rescue Etcd::EtcdError => e
  @logger.error "Etcd error #{e.class} encounter! Will attempt reconnect in " +
               "#{retry_interval} seconds."
  sleep retry_interval
  etcd_connect
  retry
rescue => e
  # I don't like doing this, but occasionally etcd-rb throws something other
  # than an EtcdError when the etcd server goes away mid-request. Otherwise if
  # the exception gets thrown, the child process gets reparented and we stop
  # heartbeating
  @logger.error "Unhandled exception: #{e.class} #{e}, Will attempt reconnect " +
               "to etcd in #{retry_interval} seconds."
  sleep retry_interval
  etcd_connect
  retry
end
