#!/usr/bin/env ruby
#
# etcd-watcher.rb 
#

require 'etcd'
require 'optparse'

args = ARGV.dup
options = {}
optparse = OptionParser.new do |o|
  o.banner = "Usage: etcd-watcher.rb [options]"

  o.on('-c', '--command COMMAND' 'Command to execute.') do |c|
    options[:cmd] = c
  end

  o.on('-h', '--heartbeat-interval [SECONDS]',
       'Interval to heartbeat etcd leader. Default: 10 seconds') do |h|
    options[:hb] = h
  end

  o.on('-k', '--key FULL_KEY_PATH', 'Full path to key to heartbeat.') do |k|
    options[:key] = k
  end

  o.on('-u', '--seed-uris [http://server1:4001,http://server2:4001]', Array,
       'List etcd server URIs. Default to http://localhost:4001.') do |u|
    options[:uri] = u
  end

  o.on('-v', '--[no-]verbose', 'Run in verbose mode. LOTS of output.') do |v|
    options[:verbose] = v
  end

  o.on_tail("-h", "--help", "Show this message") { puts o; exit }
end

optparse.parse!(args)

command = "./test.sh"

etcd = {}
etcd[:uris] = options.has_key?(:uri) ? options[:uri] : ['http://127.0.0.1:4001']
etcd[:heartbeat_freq] = options.has_key?(:hb) ? options[:hb].to_f : 10.0

client = Etcd::Client.new(etcd)
client.connect

trap("CLD") {
  Process.wait
  puts.STDERR "Child pid #{pid}: died, terminating" if options[:verbose]
  client.delete(options[:key]) 
  exit 0
}

pid = Process.spawn(options[:cmd])

trap("KILL") {
  client.delete(options[:key])
  puts "Sending SIGKILL to #{pid}" if options[:verbose]
  Process.kill(pid, 15)
  Process.wait
  puts "Exiting on SIGKILL" if options[:verbose]
  exit 0
}

loop do
  sleep 15
  client.set(options[:key], "alive", {ttl: 30})
end
