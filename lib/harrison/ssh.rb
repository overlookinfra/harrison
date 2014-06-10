require 'net/ssh'
require 'net/ssh/proxy/command'
require 'net/scp'

module Harrison
  class SSH
    def initialize(opts={})
      if opts[:proxy]
        @proxy = Net::SSH::Proxy::Command.new("ssh #{opts[:proxy]} \"nc %h %p\" 2>/dev/null")
        @conn = Net::SSH.start(opts[:host], opts[:user], forward_agent: true, proxy: @proxy)
      else
        @conn = Net::SSH.start(opts[:host], opts[:user], forward_agent: true)
      end
    end

    # Helper to catch non-zero exit status and report errors.
    def exec(command)
      puts "INFO (ssh-exec #{desc}): #{command}" if Harrison::DEBUG

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
        warn "STDERR (ssh-exec #{desc}): #{stderr_data.strip}" unless stderr_data.empty?
        warn "STDOUT (ssh-exec #{desc}): #{stdout_data.strip}" unless stdout_data.empty?
      end

      (exit_code == 0) ? stdout_data : nil
    end

    def download(remote_path, local_path)
      puts "INFO (scp-down #{desc}): #{local_path} <<< #{remote_path}" if Harrison::DEBUG
      @conn.scp.download!(remote_path, local_path)
    end

    def upload(local_path, remote_path)
      puts "INFO (scp-up #{desc}): #{local_path} >>> #{remote_path}" if Harrison::DEBUG
      @conn.scp.upload!(local_path, remote_path)
    end

    def close
      # net-ssh doesn't seem to know how to close proxy::command connections
      Process.kill("TERM", @conn.transport.socket.pid) if @proxy
      @conn.close
    end

    def closed?
      @conn.closed?
    end

    def desc
      if @proxy
        "#{@conn.host} (via #{@proxy.command_line.split(' ')[1]})"
      else
        @conn.host
      end
    end
  end
end
