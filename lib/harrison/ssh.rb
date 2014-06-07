require 'net/ssh'
require 'net/scp'

module Harrison
  class SSH
    def initialize(opts={})
      @conn = Net::SSH.start(opts[:host], opts[:user], :forward_agent => true)
    end

    # Helper to catch non-zero exit status and report errors.
    def exec(command)
      puts "INFO: (sshexec #{@conn.host}): #{command}" if Harrison::DEBUG

      stdout_data = ""
      stderr_data = ""
      exit_code = nil

      @conn.open_channel do |channel|
        channel.exec(command) do |ch, success|
          warn "Couldn't execute command (ssh.channel.exec) on remote host: #{command}" unless success

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

      warn "#{stderr_data}" unless exit_code == 0

      (exit_code == 0) ? stdout_data : nil
    end

    def close
      @conn.close
    end
  end
end
