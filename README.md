# sensu-plugin-collectd
Sensu plugin that reads a particular metric from collectd, using the collectd
socket, and ensures that it is bellow the given critical and warning thresholds.
If it is not, it will generate either a critical or warning alert in sensu. 
Otherwise, it will generate a sensu ok.

See:
https://github.com/sensu-plugins

## Installation
Use the latest version of the `check-collectd-socket-metric.rb` from releases.
See the [sensu installation instructions](http://sensu-plugins.io/docs/installation_instructions.html)

This plugin is available as a gem, so you can do
```bash
gem install sensu-plugin-collectd
```

## Collectd: what you need to know to use this plugin
To use this sensu check you need to be at least vaguely familiar with collectd. You can check [the docs](https://collectd.org/documentation.shtml). What you will need to know is the name of the metric, and the metric from the list you want to alert on. If you want to see all the metrics available in a machine:

```
~$ collectdctl LISTVAL
server-name-1-ip-172-1-2-3/collectd-cache/cache_size
server-name-1-ip-172-1-2-3/collectd-write_queue/derive-dropped
server-name-1-ip-172-1-2-3/collectd-write_queue/queue_length
server-name-1-ip-172-1-2-3/contextswitch/contextswitch
server-name-1-ip-172-1-2-3/cpu-0/cpu-idle
server-name-1-ip-172-1-2-3/cpu-0/cpu-interrupt
server-name-1-ip-172-1-2-3/cpu-0/cpu-nice
server-name-1-ip-172-1-2-3/cpu-0/cpu-softirq
server-name-1-ip-172-1-2-3/cpu-0/cpu-steal
server-name-1-ip-172-1-2-3/cpu-0/cpu-system
server-name-1-ip-172-1-2-3/cpu-0/cpu-user
server-name-1-ip-172-1-2-3/cpu-0/cpu-wait
server-name-1-ip-172-1-2-3/cpu-1/cpu-idle
server-name-1-ip-172-1-2-3/cpu-1/cpu-interrupt
server-name-1-ip-172-1-2-3/cpu-1/cpu-nice
server-name-1-ip-172-1-2-3/cpu-1/cpu-softirq
server-name-1-ip-172-1-2-3/cpu-1/cpu-steal
server-name-1-ip-172-1-2-3/cpu-1/cpu-system
server-name-1-ip-172-1-2-3/cpu-1/cpu-user
server-name-1-ip-172-1-2-3/cpu-1/cpu-wait

[...]
```

To query a particular metric:
```
~$ collectdctl GETVAL server-name-1-ip-172-1-2-3//processes-logstash/ps_count
processes=1.000000e+00
threads=7.900000e+01
```

If you want to alert on `server-name-1-ip-172-1-2-3/collectd-cache/cache_size`, youwill need to pass down the metric `collectd-cache/cache_size`

## Usage
You can run the following to display the help
```
check-collectd-socket-metric.rb -h
```

You will need to provide a warning threshold and a critical threshold, a metric ID or a regular expresion to match the metric. Optionally, you can also provide a value for the metric (if the metric id will return a list of metrics). But default it will alert on `value`

### Mandatory parameters
1. Metric id (-m --metric) or regular expression (-r --regexp). One, and only one of them must be provided.

If you want to alert on `server-name-1-ip-172-1-2-3/collectd-cache/cache_size`, youwill need to pass down the metric `-m collectd-cache/cache_size`

Alternative, a very simple regular expresion can be used: you can use `*` as a wildcard to match serveral metrics, and alert on the highest value of all of them. Only `*` as a wildcard is supported and tested. Anything else can produce unexpected behaviour. You can find an example at the end of this document. Please, ensure you test the regular expression (manually run the check) before starting to use it.

2. Warning threshold (-w --warning): warning threshold to alert on. If the metric is higher than the warning threshold, the plugin will send a warning to sensu.

3. Critical threshold (-c --critical): critical threshold to alert on. If the metric is higher than the critical threshold, the plugin will send a critical to sensu. It will only send a critical, and not a critical and a warning.

### Optional parameters

1. Path to the collectd socket (-s --socket). By default `/var/run/collectd-unisock`. If it is in a different location, this option can be used to change it.
2. Timeout (-t --timeout). 20 seconds by default. The check will timeout if it runs more than the timeout limit, sending a critical to sensu. It is provided in seconds.
3. Metric value from the metric list (-d --data_name). By default, it is `value`. If there are multiple values and we need to select one, we can use this option.



### Examples
* Alerting on a single metric
If you want to alert on `server-name-1-ip-172-1-2-3/collectd-cache/cache_size`, you will need to pass down the metric `collectd-cache/cache_size`
```bash
collectd_plugin.rb -m /uptime/uptime   -c 200400 -w 190000
```
We can expect an output like:
```bash
CheckCollectdSocket CRITICAL: host-name_1-ip-172-1-2-3/uptime/uptime[value] =  = 192291.00 is over the warning limit (190000.00)
```

* Alerting in a set of metrics
If for example, we have 8 CPUs, and we want to alert if any of them goes above certain usage, we can use the regexp option:
```bash
 collectd_plugin.rb -r "cpu-*/cpu-idle" -c 99 -w 80
```
We can expect an output like:
```bash
CheckCollectdSocket WARNING: clickhouse-server-shard_1-ip-172-26-161-164/cpu-4/cpu-idle[value] = 97.93 is over the warning limit (80.00)
```

*. Specifying a different metric value
If we have a ps_count metric that will return processes and threads, we can alert on the number of threads by setting the data_name:
```bash
collectd_plugin.rb -m processes-collectd/ps_count -c 10 -w 8 -d threads
```
It will return something like this:
```bash
CheckCollectdSocket CRITICAL: clickhouse-server-shard_1-ip-172-26-161-164/processes-collectd/ps_count[threads] = 12.00 is over the critical limit (10.00)
```

*. Changing the socket path
If the collectd socket is in a different location to the default, we can set it:
```bash
collectd_plugin.rb -m processes-collectd/ps_count -c 10 -w 8 -d threads -s /var/run/collectd-unisock
```

*. Changing the default timeout
We can set a custom timeout for the check with --timeout (seconds)
```bash
collectd_plugin.rb -m processes-collectd/ps_count -c 10 -w 8 -d threads -t 10
```