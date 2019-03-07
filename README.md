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
