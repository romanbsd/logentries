require 'spec_helper'

describe Logentries::Sender do
  before do
    Logentries::Sender.any_instance.stub(:create_socket!)
  end

  let(:sender) { Logentries::Sender.new('key', 'host', 'app').start }
  let(:socket) { mock('socket', :closed? => false) }

  describe "Robustness" do
    it "restarts thread when it's dead" do
      sender.should_receive(:start)
      sender.instance_variable_get(:@thread).kill
      sleep 0.1
      sender.write('test')
    end

    class MockSocket
      def initialize
        @count = 0
      end

      def write(buf)
        if @count > 0
          return buf.length
        end
        @count += 1
        raise EOFError
      end
    end

    it "re-creates the socket and retries on error" do
      # Won't work for other thread for some reason
      # socket.should_receive(:write).and_raise(EOFError)
      # socket.should_receive(:write).and_return(2)
      # sender.stub(:socket) { socket }
      socket = MockSocket.new
      sender.instance_variable_set(:@socket, socket)

      sender.should_receive(:create_socket!)
      sender.write('ERROR')
      sender.write('OK')
    end
  end

  context "Shutting down" do
    it "closes the socket" do
      socket.should_receive(:close)
      sender.stub(:socket) { socket }
      sender.close
    end

    it "terminates the thread" do
      alive = proc { sender.instance_variable_get(:@thread).alive? }
      expect { sender.close }.to change(&alive).from(true).to(false)
    end
  end
end