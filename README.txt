Usage: etcd-watcher.rb [options]
    -c, --command COMMAND            Command to execute.
    -h, --heartbeat [SECONDS]        Interval to heartbeat etcd leader. Default: 10 seconds
    -k, --key FULL_KEY_PATH          Full path to key to heartbeat.
    -r, --retry [RETRY_INTERVAL]     How many seconds to wait before retrying if etcd is unavailable
    -u [http://server1:4001,http://server2:4001],
        --uris                       List etcd server URIs. Default to http://localhost:4001.
    -v, --[no-]verbose               Run in verbose mode: log at debug
        --help                       Show this message
