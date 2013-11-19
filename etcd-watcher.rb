#!/usr/bin/env ruby
#
# etcd-watcher.rb
#

require 'etcd'
require 'optparse'
require 'logger'

logger = Logger.new(STDOUT)

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

  ## TODO: Make this toggle loglevel
  o.on('-v', '--[no-]verbose', 'Run in verbose mode. LOTS of output.') do |v|
    options[:verbose] = v
  end

  o.on_tail("-h", "--help", "Show this message") { puts o; exit }
end

retry_interval = options.has_key?(:retry_interval) ? options[:retry_interval] : 30

optparse.parse!(args)

@etcd = {}
@etcd[:uris] = options.has_key?(:uri) ? options[:uri] : ['http://127.0.0.1:4001']
@etcd[:heartbeat_freq] = options.has_key?(:hb) ? options[:hb].to_f : 10.0

def etcd_connect
  @client = Etcd::Client.new(@etcd)
  @client.connect
end

def terminate_pid(pid)
  Process.kill(pid, 15)
  Process.wait
end

process = Process.spawn(options[:cmd])
pid = process.to_i

trap("CLD") {
  Process.wait
  status = $?.exitstatus
  puts "Child pid #{$?.pid}: died with status #{status}, terminating supervisor" if options[:verbose]
  @client.delete(options[:key])
  exit status
}

#trap("INT") {
#  logger.error "Interrupted!"
#  Process.kill(pid, 2)
#  Process.wait
#  logger.error "lol"
#}

trap("TERM") {
  @client.delete(options[:key])
  puts "Sending SIGTERM to #{pid}" if options[:verbose]
  Process.kill(pid, 15)
  Process.wait
  puts "Exiting on SIGTERM" if options[:verbose]
  exit 0
}

etcd_connect

begin
  loop do
    @client.set(options[:key], "alive", {ttl: 30})
    sleep 15
  end
rescue Etcd::EtcdError => e
  logger.error "Etcd error #{e.class} encounter! Will attempt reconnect in #{retry_interval} seconds."
  sleep retry_interval
  etcd_connect
  retry
rescue => e
  # I don't like doing this, but occasionally etcd-rb throws something other than an EtcdError
  # when the etcd server goes away.
  logger.error "Unhandled exception: #{e.class} #{e}"
  sleep retry_interval
  etcd_connect
  retry
end
