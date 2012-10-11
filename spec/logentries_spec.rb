require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Logentries::Logger do
  let(:logger) { Logentries::Logger.new('key', 'host', 'app') }
  let(:logdev) { logger.instance_variable_get(:@logdev) }

  describe "Sockets" do
    it "retries on error" do
      logdev.socket.stub_once(:write).and_raise_error(EOFError)
      logger.info "testing"
    end
  end

  describe "Logging" do
    # before do
    #   Logentries::Sender.any_instance.stub(:create_socket!)
    # end

    it "formats the message" do
      socket = mock(:socket)
      logdev.stub(:socket) { socket }
      socket.should_receive(:write) do |msg|
        msg.should end_with("testing\r\n")
      end

      logger.info "\nThis is a test\n"
      sleep 0.1
    end
  end
end
