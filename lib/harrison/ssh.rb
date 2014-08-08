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

    def exec(command)
      puts "INFO (ssh-exec #{desc}): #{command}" if Harrison::DEBUG

      result = invoke(@conn, command)

      if Harrison::DEBUG || result[:status] != 0
        warn "STDERR (ssh-exec #{desc}): #{result[:stderr]}" unless result[:stderr].empty?
        warn "STDOUT (ssh-exec #{desc}): #{result[:stdout]}" unless result[:stdout].empty?
      end

      (result[:status] == 0) ? result[:stdout] : nil
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

    def host
      @conn.host
    end

    protected
    # ----------------------------------------

    def invoke(conn, cmd)
      stdout_data = ""
      stderr_data = ""
      exit_code = nil

      conn.open_channel do |channel|
        channel.exec(cmd) do |ch, success|
          warn "Couldn't execute command (ssh.channel.exec) on remote host: #{cmd}" unless success

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

      conn.loop

      { status: exit_code, stdout: stdout_data.strip, stderr: stderr_data.strip }
    end
  end
end
