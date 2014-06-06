require 'net/ssh'
require 'net/scp'

module Harrison
  class SSH
    def initialize(opts={})
      @conn = Net::SSH.start(opts[:host], opts[:user], :forward_agent => true)
    end

    # Helper to catch non-zero exit status and report errors.
    def exec(command)
      stdout_data = ""
      stderr_data = ""
      exit_code = nil

      @conn.open_channel do |channel|
        channel.exec(command) do |ch, success|
          abort "FAILED: couldn't execute command (ssh.channel.exec)" unless success

          channel.on_data do |ch,data|
            stdout_data += data
          end

          channel.on_extended_data do |ch,type,data|
            stderr_data += data
          end

          channel.on_request("exit-status") do |ch,data|
            exit_code = data.read_long
          end
        end
      end

      @conn.loop

      (exit_code == 0) ? stdout_data : stderr_data
    end

    def close
      @conn.close
    end
  end
end
