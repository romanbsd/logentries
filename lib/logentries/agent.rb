require 'net/http'

module Logentries
  # A Linux 3.0+ only agent that reports the CPU, memory, network
  # and disk utilization to Logentries.
  class Agent
    API = 'api.logentries.com'.freeze
    FILES = {
      :cpu => '/proc/stat',
      :mem => '/proc/meminfo',
      :net => '/proc/net/dev',
      :disk => '/proc/diskstats'
    }.freeze
    MEM_FIELDS = ['MemTotal:', 'Active:', 'Cached:'].freeze

    # @see #initialize
    def self.start(host_key)
      Thread.new {
        new(host_key).start
      }
    end

    # Create a new instance of the agent
    #
    # @param [String] host_key 36 character host key
    def initialize(host_key)
      @host_key = host_key
      @prev_stat = Hash.new(0)
      @stat = {}
      @files = FILES.each_with_object({}) { |(stat, file), h| h[stat] = File.open(file, 'r') }
      @devices = Dir.glob('/sys/block/*').reject {|dev| dev =~ %r{/ram|/loop}}.map {|dev| dev.sub('/sys/block/', '')}
    # rescue Errno::ENOENT
    end

    def start
      loop do
        collect_stats
        send_stats
        sleep 5
      end
    rescue => e
      STDERR.puts e.message
      retry
    end

    private

    # Read a file for the stat
    #
    # @param [Symbol] stat
    # @return [String] file body
    def read_stat(stat)
      @files[stat].rewind
      @files[stat].read
    end

    def collect_stats
      [:cpu_stats, :mem_stats, :net_stats, :disk_stats].each { |stat| send(stat) }
    end

    # Send the stats to Logentries
    #
    # @return [Net::HTTPResponse] response
    def send_stats
      first_time = @prev_stat.empty?
      stats = build_request
      @stat.keys.each { |k| stats[k] = @stat[k] - @prev_stat[k] }
      @prev_stat.replace(@stat)
      # These should be reported as absolute values
      [:mt, :ma, :mc].each {|k| @prev_stat[k] = 0}
      return if first_time

      req = Net::HTTP::Post.new('/')
      req.set_form_data(stats)
      res = Net::HTTP.start(API, use_ssl: true) { |http| http.request(req) }
      unless res.is_a?(Net::HTTPOK)
        STDERR.puts "Error sending stat: #{res.message}"
      end
      res
    end

    def build_request
      {
        request: 'push_wl',
        host_key: @host_key
      }
    end

    def disk_stats
      lines = read_stat(:disk)
      reads = writes = 0
      lines.each_line do |line|
        fields = line.split(/\s+/)
        next unless @devices.include?(fields[2])
        reads += fields[5].to_i
        writes += fields[7].to_i
      end

      @stat[:dr] = reads
      @stat[:dw] = writes
    end

    def mem_stats
      lines = read_stat(:mem)
      total_fields = MEM_FIELDS.size
      stats = Array.new(total_fields)
      count = 0
      lines.each_line do |line|
        fields = line.split(/\s+/)
        if i = MEM_FIELDS.index(fields.first)
          stats[i] = fields[1].to_i
          count += 1
        end
        break if count == total_fields
      end

      [:mt, :ma, :mc].each_with_index do |stat, i|
        @stat[stat] = stats[i]
      end
    end

    def net_stats
      lines = read_stat(:net)
      rx = tx = 0
      lines.each_line do |line|
        next unless line =~ /^\s*(?:eth|wlan)/
        fields = line.split(/\s+/)
        rx += fields[2].to_i
        tx += fields[10].to_i
      end

      @stat[:ni] = rx
      @stat[:no] = tx
    end

    def cpu_stats
      lines = read_stat(:cpu)
      line = lines.split("\n").find {|l| l.start_with?('cpu ')}
      fields = line.split(/\s+/)[1..7]
      [:cu, :cl, :cs, :ci, :cio, :cq, :csq].each_with_index do |stat, i|
        @stat[stat] = fields[i].to_i
      end
    end
  end
end

if $0 == __FILE__
  raise ArgumentError.new("Usage: #{$0} host-key") unless ARGV.size == 1
  Logentries::Agent.new(ARGV[0]).start
end
