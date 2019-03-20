#!/usr/bin/env ruby
#
#   check-collectd-socket-metric.rb
#
# DESCRIPTION:
#   This plugin retrieves a metric from the collectd socket, and verifies
#   that it is within the provided thresholds (critical and warning)
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: rspec (for the tests)
#
# USAGE:
#   check-collectd-socket-metric.rb (-m <metric_id> | -r <metric id regexp>)
#      -w <warning threshold> -c <critical threshold> [-d <metric value>]
#      [-t <timeout>] [-s <socket path>]
#
# LICENSE:
#   Copyright: Maria Pilar Gomez Moya (mp.gomezmoya@gmail.com) and Bartosz Lassak
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'net/http'
require 'socket'
require 'timeout'

# Encapsulates the interaction with the IOBuffer so we can have something
# we can mock in the tests, something that we can open and close (effectively
# clearing the buffer) and is more decaupled from the main class
class SocketWrapper
  attr_reader :socket_path
  def initialize(
      socket_path
  )
    @socket = nil
    @socket_path = socket_path
  end

  def open
    @socket = Net::BufferedIO.new(UNIXSocket.new(@socket_path))
  end

  def close
    if ! @socket.closed
      @socket.close
    end
  end

  def closed
    return @socket.closed
  end

  def readline
    return @socket.readline
  end

  def write(line)
    return @socket.write(line)
  end
end

# Class with all the logic, separate from the actual Sensu Check, so it can be
# properly tested
class CheckCollectdComponent
  def initialize(
      socket,
      critical,
      warning,
      metric,
      regexp,
      data_name,
      timeout,
      cli_handler
  )
    @socket = socket
    @critical = critical
    @warning = warning
    @metric = metric
    @regexp = regexp
    @data_name = data_name
    @timeout = timeout
    @cli_handler = cli_handler
  end

  def critical(message)
      @cli_handler.critical message
      @socket.close
  end

  def warning(message)
      @cli_handler.warning message
      @socket.close
  end

  def ok(message)
      @cli_handler.ok message
      @socket.close
  end

  def isFloat(string_option)
    # We want to know if the option passed down in command line can be
    # safely converted to a valid float. If not, we want to catch the
    # exception and return an error, finishing the script.
    begin
       return !!Float(string_option)
    rescue
      return false
    end
  end

  def formatedFloatString(float_number)
    return "#{float_number.round(2)}"
  end

  # Verifies that the class attributes are valid: that they are not nil,
  # and they are the expected data type (so we are not trying to use
  # strings in the place of integers)
  def validateArguments()
    # XXX extract error messages to different file
    # NULL checks
    if @socket == nil
      return false, "The socket can't be nil"
    end
    if @critical == nil
      return false, "Critical can't be nil"
    end
    if @warning == nil
      return false, "Warning can't be nil"
    end
    if @metric == nil
      return false, "Metric can't be nil"
    end
    if @data_name == nil
      return false, "Data name can't be nil"
    end
    if @timeout == nil
      return false, "Timeout can't be nil"
    end
    if @cli_handler == nil
      return false, "The cli handler can't be nil"
    end
    # Validate data type
    if !self.isFloat(@critical)
      return false, "Critical has to be a number"
    elsif @critical.to_f < 0
      return false, "Critical has to be a positive number"
    end
    if !self.isFloat(@warning)
      return false, "Warning has to be a number"
    elsif @warning.to_f < 0
      return false, "Warning has to be a positive number"
    end
    if !self.isFloat(@timeout)
      return false, "Timeout has to be a number"
    elsif @timeout.to_f < 0
      return false, "Timeout has to be a positive number"
    end
    return true, ""
  end

  # Formats arguments and ensures that they have the correct data type
  def formatArguments()
    self.prependSlashInMetric
    @critical = @critical.to_f
    @warning = @warning.to_f
    @timeout = @timeout.to_f
  end

  # Reads the first line of the results of either GETVAL or LISTVAL
  # and parses the number of lines that need to be read
  #
  # Returns the number of lines to be read in the socket
  def getNumResultsInSocket(line)
    # The first line will be the number of results in the format
    # "XXX Values found". We need that number to loop and parse every single entry
    # end
    return (line.strip.split(" ")[0]).to_i
  end

  # Ensures that the metric string starts with "/" so the metric_id is
  # constructer correctly
  def prependSlashInMetric
    if @metric[0] != "/"
      @metric = "/"+@metric
    end
  end

  # Concatenates hostname and metric to get the metric id to pass down to
  # the collectd GETVAL
  #
  # Returns the fully constructed metric id
  def buildMetricId(socket)
    socket.readline
    hostname = socket.readline.strip.split(" ")[1].strip.split("/")[0]
    return hostname + @metric
  end

  # Reads the results of the GETVAL from the socket, and builds a map
  # with all the values returned for the given metric id
  #
  # Returns a key value map with the values list
  def buildValueHash(socket)
    line = socket.readline
    if line == "ERROR: Server error: No such value."
      return nil
    end
    num_lines = self.getNumResultsInSocket(line)
    values = Hash.new
    for i in 1..num_lines
      rawline = socket.readline
      line = rawline.to_s.split("=")
      values[:"#{line[0]}"] = "%f" % line[1].to_f
    end
    return values
  end

  # Runs the sensu check, sending the calling sensu with either critical,
  # warning or ok.
  #
  # XXX use exceptions in case of error instead of generating a critical and
  # just returning
  def run_check
    begin
      @socket.open
    rescue => e
      return self.critical "Tried to access UNIX domain socket (#{@socket.socket_path}) but failed: #{e}"
    end

    begin
      # XXX move to separate function (findMetricId)
      # Read all metrics ids
      @socket.write("LISTVAL\n")
      metric_id = buildMetricId(@socket)
      @socket.close
      @socket.open
      # If the metric hasn't been found, error
      if metric_id == nil
        puts "Could not find the metric that matches metric #{@metric}"
        self.critical "Could not find the metric that matches #{@metric}, the metric #{}"
        return
      end
      # Read a metric
      query = "GETVAL #{metric_id}\n"
      @socket.write(query)
      values = self.buildValueHash(@socket)
      if values == nil
        self.critical "The metric #{@metric} does not exist in this host."
        return
      end
      @socket.close
    rescue => e
      self.critical "An error occured while trying to use the socket (#{@socket.socket_path}) : #{e}"
    end
    # TODO check if the particular value is present in the map
    # Check critical threshold
    current_value = values[:"#{@data_name}"]
    if current_value == nil or current_value == ""
      self.critical "Metric value #{@data_name} not found in the list"
      return
    end
    if current_value.to_f > @critical.to_f
      self.critical "#{metric_id} #{@data_name} = #{current_value}, which is over the critical limit (#{@critical})"
      return
    end
    if current_value.to_f > @warning.to_f
      self.warning "#{metric_id} #{@data_name} = #{current_value}, which is over the warning limit (#{@warning})"
      return
    end
    self.ok "#{metric_id} is within threshold"
  end

  # Main function. It will validate the class attribute, ensure they have
  # the correct format, and run the check with a timeout.
  def run
    # First, validate that the arguments passed to the handler are valid.
    # If the are not, print an error and exit
    is_valid, error_message = self.validateArguments
    if !is_valid
      puts "ERROR: #{error_message}"
      if @socket != nil
        @socket.close
      end
      return
    end
    # Ensure correct data types and format
    self.formatArguments
    # Run the check with a timeout
    begin
      Timeout::timeout(@timeout.to_i) do
        self.run_check
      end
    rescue => e
      @socket.close
      @cli_handler.critical "#{@metric} timed out"
    end
  end
end

# Sensu check. The only thing it does is initialize the socket,
# parses the command lines arguments and instantiates the component,
# that will do the actual run()
class CheckCollectdSocket < Sensu::Plugin::Check::CLI
  option :socket,
         description: 'Supervisor UNIX domain socket (optional)',
         short: '-s SOCKET',
         long: '--socket SOCKET',
         default: '/var/run/collectd-unixsock'

  option :critical,
         description: 'Value over wich the metric generate a critical alert',
         short: '-c <critical threshold>',
         long: '--crtical <critical threshold>'

  option :warning,
         description: 'Value over wich the metric generate a warning alert',
         short: '-w <warning threshold>',
         long: '--warning <warning threshold>'

  option :metric,
         description: 'Metric we want to evaluate, for example, \"processes-carbon-clickhouse/ps_count\"',
         short: '-m <metric id>',
         long: '--metric <metric id>',
         default: nil

  option :data_name,
         description: 'When expect a list of values in that metric, data name must be given. Default is \"value\"',
         short: '-d <data name>',
         long: '--data_name <data name>',
         default: 'value'

  option :help,
         description: 'Show help',
         short: '-h',
         long: '--help'

  option :timeout,
         description: 'Socket timeout connection',
         short: '-t',
         long: '--timeout',
         default: 20

  option :regexp,
         description: 'Regular expresion to match serveral metrics ids. Cannot be used with the \"metric\" option',
         short: '-r',
         long: '--regexp',
         default: nil

  def run
    if config[:help]
      puts opt_parser
      exit
    end
    socket = SocketWrapper.new(config[:socket])
    component = CheckCollectdComponent.new(socket,
                                           config[:critical],
                                           config[:warning],
                                           config[:metric],
                                           config[:regexp],
                                           config[:data_name],
                                           config[:timeout],
                                           self)
    begin
      component.run
    rescue => e
      critical "Unexpected exception when trying to read #{config[:socket]} (#{e})"
    end
  end
end
