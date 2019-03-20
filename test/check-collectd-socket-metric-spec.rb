require '../bin/check-collectd-socket-metric'

# Pretends to be the collectd socket
class SocketWrapperMock
  attr_reader :is_open
  attr_accessor :socket_path
  def initialize(return_string, sleep_seconds = 5)
    @return_string = return_string
    @current_line = 0
    @sleep_seconds = sleep_seconds
    @is_open = false
    @socket_path = "I/am/a/socket/path"
  end

  def readline
    @current_line += 1
    if @return_string.size < @current_line
      sleep @sleep_seconds
    end
    return @return_string[@current_line - 1]
  end

  def open
    @is_open = true
  end

  def close
    @is_open = false
  end

  def write(line)
    # NO-OP
  end

  def populate(new_strings)
    @return_string = new_strings
    @current_line = 0
  end
end

class CliHandlerMock < Sensu::Plugin::Check::CLI
end

describe CheckCollectdSocket do
  before :each do
    @socket = '/var/run/collectd-unixsock'
    @metric = '/cpu-0/cpu-user'
    @data_name = 'value'
    @warning = '3'
    @critical = '5'
    @metric_id = 'hostname/id/id'
    @timeout_secs = '2'
    @is_socket_open = false
  end

  after(:each) do
    #Ensure that every outcome returns an exit code
    expect(@is_socket_open).to eq(false)
  end

  context 'if the inital "/" is omitted from the metric' do
    let(:wrapper) {SocketWrapperMock.new([])}
    let(:cli_handler) {instance_double(CliHandlerMock)}
    let(:check) {CheckCollectdComponent.new(wrapper,
                                            @critical,
                                            @warning,
                                            "id/id",
                                            nil,
                                            "value",
                                            @timeout_secs,
                                            cli_handler)}
    it 'should match the metric even if hte initial \"/\" is omitted' do
      wrapper.populate(["1 Value found",
                        "094023 hostname/id/id",
                        "1 Value found",
                        "value=2"])

      # Ensure we are querying "hostname/id/id and not "hostnameid/id"
      expect(cli_handler).to receive(:ok).with("hostname/id/id is within threshold")
      check.run
      @is_socket_open = wrapper.is_open
    end
  end

  context 'With valid data' do
    let(:wrapper) {SocketWrapperMock.new([])}
    let(:cli_handler) {instance_double(CliHandlerMock)}
    let(:check) {CheckCollectdComponent.new(wrapper,
                                            @critical,
                                            @warning,
                                            "/id/id",
                                            nil,
                                            "value",
                                            @timeout_secs,
                                            cli_handler)}

    # OK
    it 'should return ok when not reaching any threshold' do
      wrapper.populate(["1 Value found",
                        "094023 hostname/id/id",
                        "1 Value found",
                        "value=2"])
      expect(cli_handler).to receive(:ok).with("hostname/id/id is within threshold")
      check.run
      @is_socket_open = wrapper.is_open
    end

    # Warning
    it 'should return warning when hitting the threshold' do
      wrapper.populate(["1 Value found",
                        "094023 hostname/id/id",
                        "1 Value found",
                        "value=4"])

      expect(cli_handler).to receive(:warning).with("hostname/id/id value = 4.000000, which is over the warning limit (3.0)")
      check.run
      @is_socket_open = wrapper.is_open
    end

    # TODO format the value
    # Critical
    it 'should return critical when hitting the critical threshold' do
      wrapper.populate(["1 Value found",
                        "094023 #{@metric_id}",
                        "1 Value found",
                        "value=6"])

      expect(cli_handler).to receive(:critical).with("#{@metric_id} value = 6.000000, which is over the critical limit (5.0)")
      check.run
      @is_socket_open = wrapper.is_open
    end

    # Timeout
    it 'should timeout when there are less lines to read than expected' do
      message = "/id/id timed out"
      wrapper.populate(["1 Value found",
                        "094023 hostname/id/id",
                        "2 Values found",
                        "value=2"])
      expect(cli_handler).to receive(:critical).with(message)
      check.run
      # In the case of timeout, the socket would be closed by CheckCollectdSocket
      # insteand of the component
      # TODO move to a different context witout the after check
      # @is_socket_open = wrapper.is_open
    end
    it 'should return a critical if the metric is not found' do
      message="The metric /id/id does not exist in this host."
      wrapper.populate(["1 Value found",
                        "094023 hostname/id/id",
                        "ERROR: Server error: No such value."])
      expect(cli_handler).to receive(:critical).with(message)
      check.run
      @is_socket_open = wrapper.is_open
    end
    # TODO test floats
  end

  # INVALID ARGUMENT TESTS
  context 'With missing or wrong arguments' do
    let(:wrapper) {SocketWrapperMock.new([])}
    let(:cli_handler) {instance_double(CliHandlerMock)}
    context "With null socket" do
      let(:check) {CheckCollectdComponent.new(nil,
                                              @critical,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: The socket can't be nil")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With null critical" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              nil,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Critical can't be nil")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With null warning" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              nil,
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Warning can't be nil")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With null metric" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              @warning,
                                              nil,
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Metric can't be nil")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With null value" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              nil,
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Data name can't be nil")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With null timeout" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              nil,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Timeout can't be nil")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With null cli handler" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              nil)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: The cli handler can't be nil")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With non numeric critical" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              "invalid",
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Critical has to be a number")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With non numeric warning" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              "invalid",
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Warning has to be a number")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With non numeric timeout" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              "invalid",
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Timeout has to be a number")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With negative critical" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              -0.5,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Critical has to be a positive number")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With negative warning" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              -3,
                                              "/id/id",
                                              nil,
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Warning has to be a positive number")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With negative tiemout" do
      let(:check) {CheckCollectdComponent.new(wrapper,
                                              @critical,
                                              @warning,
                                              "/id/id",
                                              nil,
                                              "value",
                                              -8.0,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Timeout has to be a positive number")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
  end
  # REGEXP TESTS
  context 'Using the regexp parameter' do
    context "If we provide both metric and regexp" do
      let(:wrapper) {SocketWrapperMock.new([])}
      let(:cli_handler) {instance_double(CliHandlerMock)}
      let(:check) {CheckCollectdComponent.new(nil,
                                              @critical,
                                              @warning,
                                              "/id/id",
                                              "/cpu*/usage",
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return an error' do
        expect(STDOUT).to receive(:puts).with("ERROR: Only one of the options, metric or regexp, can be provided")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
    context "With valid data" do
      let(:wrapper) {SocketWrapperMock.new(["3 Value found",
                        "094023 hostname/cpu1/usage",
                        "094023 hostname/cpu2/usage",
                        "094023 hostname/cpu3/usage",
                        "1 Value found",
                        "value=1",
                        "1 Value found",
                        "value=2",
                        "1 Value found",
                        "value=2"])}
      let(:cli_handler) {instance_double(CliHandlerMock)}
      let(:check) {CheckCollectdComponent.new(nil,
                                              @critical,
                                              @warning,
                                              nil,
                                              "/cpu*/usage",
                                              "value",
                                              @timeout_secs,
                                              cli_handler)}
      it 'should return ok when everything is bellow the threshold' do
        expect(cli_handler).to receive(:ok).with("Everything matching hostname/cpu*/usage is within threshold")
        check.run
        @is_socket_open = wrapper.is_open
      end
      it 'should return critical when something is above the critical threshold' do
        wrapper.populate(["3 Value found",
                        "094023 hostname/cpu1/usage",
                        "094023 hostname/cpu2/usage",
                        "094023 hostname/cpu3/usage",
                        "1 Value found",
                        "value=1",
                        "1 Value found",
                        "value=4",
                        "1 Value found",
                        "value=6"])
        expect(cli_handler).to receive(:critical).with("#{@metric_id} value = 6.000000, which is over the critical limit (5.0)")
        check.run
        @is_socket_open = wrapper.is_open
      end
      it 'should return warning when something is above the warning threshold' do
        wrapper.populate(["3 Value found",
                        "094023 hostname/cpu1/usage",
                        "094023 hostname/cpu2/usage",
                        "094023 hostname/cpu3/usage",
                        "1 Value found",
                        "value=1",
                        "1 Value found",
                        "value=4",
                        "1 Value found",
                        "value=2"])
        expect(cli_handler).to receive(:critical).with("#{@metric_id} value = 4.000000, which is over the critical limit (3.0)")
        check.run
        @is_socket_open = wrapper.is_open
      end
    end
  end
end
