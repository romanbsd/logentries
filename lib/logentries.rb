require 'socket'
require 'openssl'
require 'thread'
require 'logger'

module Logentries

  # @private
  class Sender

    attr_reader :socket
    def initialize(key, host, service)
      @path = "/#{key}/hosts/#{host}/#{service}/?realtime=1"
      create_socket!
    end

    def write(str)
      start unless @thread.alive?
      queue << str.strip + "\r\n"
    end

    def start
      @thread = Thread.new {
        Thread.current[:label] = self.class.to_s
        while msg = queue.pop do
          begin
            socket.write(msg)
          rescue Exception => e
            puts "ERROR: #{e.class.to_s} #{e.message} #{e.inspect}"
            create_socket!
            retry
          end
        end
      }
      self
    end

    def close
      queue << nil
      destroy_socket!
      @thread.join
    end

    private
    def queue
      @queue ||= Queue.new
    end

    def create_socket!
      sock = TCPSocket.new('api.logentries.com', 443)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
      destroy_socket!
      @socket = OpenSSL::SSL::SSLSocket.new(sock, ctx).tap do |socket|
        socket.sync_close = true
        socket.connect
        socket.write("PUT #{@path} HTTP/1.1\r\n\r\n")
      end
    rescue IOError, Errno::ECONNRESET
      retry
    end

    def destroy_socket!
      return unless socket
      socket.close unless socket.closed?
    rescue IOError
    ensure
      @socket = nil
    end
  end

  # @public
  class Logger < ::Logger
    def initialize(key, host = nil, app = nil)
      @level = DEBUG
      @default_formatter = Formatter.new
      host ||= Socket.gethostname
      app ||= if defined?(Rails)
        Rails::Application.subclasses.first.to_s.gsub(/::.*/, '').downcase
      else
        $0
      end
      @logdev = Sender.new(key, host, app).start
    end

    class Formatter < ::Logger::Formatter
      def msg2str(msg)
        super.strip
      end
    end
  end

end
