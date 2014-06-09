require 'net/ssh'
require 'net/scp'

module Harrison
  class SSH
    def initialize(opts={})
      @conn = Net::SSH.start(opts[:host], opts[:user], :forward_agent => true)
    end

    # Helper to catch non-zero exit status and report errors.
    def exec(command)
      puts "INFO (sshexec #{@conn.host}): #{command}" if Harrison::DEBUG

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

      if Harrison::DEBUG || exit_code != 0
        warn "STDERR (sshexec #{@conn.host}): #{stderr_data.strip}" unless stderr_data.empty?
        warn "STDOUT (sshexec #{@conn.host}): #{stdout_data.strip}" unless stdout_data.empty?
      end

      (exit_code == 0) ? stdout_data : nil
    end

    def download(remote_path, local_path)
      @conn.scp.download!(remote_path, local_path)
    end

    def upload(local_path, remote_path)
      # TODO
    end

    def close
      @conn.close
    end
  end
end
