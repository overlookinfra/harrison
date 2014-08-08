require 'spec_helper'

describe Harrison::SSH do
  before(:all) do
    Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
    Harrison.const_set("DEBUG", false)
  end

  after(:all) do
    Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
  end

  before(:each) do
    @mock_ssh_chan = double(:ssh_channel)

    @mock_ssh_conn = double(:ssh_conn, host: 'test.example.com')
    allow(@mock_ssh_conn).to receive(:loop)
    allow(@mock_ssh_conn).to receive(:open_channel).and_yield(@mock_ssh_chan)

    allow(Net::SSH).to receive(:start).and_return(@mock_ssh_conn)
  end

  let(:instance) { Harrison::SSH.new(host: 'test.example.com', user: 'test_user') }

  describe 'initialize' do
    it 'should open an SSH connection' do
      expect(Net::SSH).to receive(:start).with('test.example.com', 'test_user', anything).and_return(double(:ssh_conn))

      Harrison::SSH.new(host: 'test.example.com', user: 'test_user')
    end

    context 'when passed a :proxy option' do
      it 'should open an SSH connection with a proxy command' do
        proxy = double(:ssh_proxy)

        expect(Net::SSH::Proxy::Command).to receive(:new).and_return(proxy)
        expect(Net::SSH).to receive(:start).with('test.example.com', 'test_user', { forward_agent: true, proxy: proxy, timeout: 10 }).and_return(double(:ssh_conn))

        Harrison::SSH.new(host: 'test.example.com', user: 'test_user', proxy: 'test-proxy.example.com')
      end
    end
  end

  describe '#exec' do
    it 'should exec the passed command on an SSH connection channel' do
      command = "pwd"
      expect(@mock_ssh_chan).to receive(:exec).with(command)

      instance.exec(command)
    end

    context 'when the command exits non-zero' do
      before(:each) do
        allow(instance).to receive(:invoke).with(@mock_ssh_conn, anything).and_return({ status: 1, stdout: 'standard output', stderr: 'standard error' })
      end

      it 'should warn whatever the command emitted to stdout' do
        output = capture(:stderr) do
          instance.exec('cat noexist 2>/dev/null')
        end

        expect(output).to include('stdout', 'standard output')
      end

      it 'should warn whatever the command emitted to stderr' do
        output = capture(:stderr) do
          instance.exec('cat noexist 2>/dev/null')
        end

        expect(output).to include('stderr', 'standard error')
      end

      it 'should return nil' do
        capture(:stderr) do
          expect(instance.exec('cat noexist 2>/dev/null')).to be_nil
        end
      end
    end

    context 'when --debug is set' do
      before(:each) do
        allow(instance).to receive(:invoke).with(@mock_ssh_conn, anything).and_return({ status: 0, stdout: 'standard output', stderr: 'standard error' })
      end

      before(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
        Harrison.const_set("DEBUG", true)
      end

      after(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
        Harrison.const_set("DEBUG", false)
      end

      it 'should output the command being run' do
        output = capture(:stdout) do
          capture(:stderr) do
            instance.exec('touch testfile')
          end
        end

        expect(output).to include('info', 'touch testfile')
      end

      it 'should warn whatever the command emitted to stdout' do
        output = capture(:stderr) do
          capture(:stdout) do
            instance.exec('touch testfile')
          end
        end

        expect(output).to include('stdout', 'standard output')
      end

      it 'should warn whatever the command emitted to stderr' do
        output = capture(:stderr) do
          capture(:stdout) do
            instance.exec('touch testfile')
          end
        end

        expect(output).to include('stderr', 'standard error')
      end
    end
  end

  describe '#download' do
    before(:each) do
      @mock_scp = double(:net_scp)
      allow(@mock_ssh_conn).to receive(:scp).and_return(@mock_scp)
    end

    it 'should delegate to net-scp' do
      expect(@mock_scp).to receive(:download!).with('remote', 'local')

      instance.download('remote', 'local')
    end

    context 'when --debug is set' do
      before(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
        Harrison.const_set("DEBUG", true)
      end

      after(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
        Harrison.const_set("DEBUG", false)
      end

      it 'should output what is being downloaded and to where' do
        expect(@mock_scp).to receive(:download!).with('remote', 'local')

        output = capture(:stdout) do
          instance.download('remote', 'local')
        end

        expect(output).to include('scp-down', 'local', 'remote')
      end
    end
  end

  describe '#upload' do
    before(:each) do
      @mock_scp = double(:net_scp)
      allow(@mock_ssh_conn).to receive(:scp).and_return(@mock_scp)
    end

    it 'should delegate to net-scp' do
      expect(@mock_scp).to receive(:upload!).with('local', 'remote')

      instance.upload('local', 'remote')
    end

    context 'when --debug is set' do
      before(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
        Harrison.const_set("DEBUG", true)
      end

      after(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
        Harrison.const_set("DEBUG", false)
      end

      it 'should output what is being uploaded and to where' do
        expect(@mock_scp).to receive(:upload!).with('local', 'remote')

        output = capture(:stdout) do
          instance.upload('local', 'remote')
        end

        expect(output).to include('scp-up', 'local', 'remote')
      end
    end
  end

  describe '#close' do
    it 'should delegate to net-ssh' do
      expect(@mock_ssh_conn).to receive(:close)

      instance.close
    end

    context 'when using a proxy command' do
      before(:each) do
        @proxy = double(:ssh_proxy)
        instance.instance_variable_set(:@proxy, @proxy)
      end

      it 'should send TERM to the proxy command' do
        allow(@mock_ssh_conn).to receive(:transport).and_return(double(:transport, socket: double(:socket, pid: 100000)))

        expect(Process).to receive(:kill).with("TERM", 100000)
        expect(@mock_ssh_conn).to receive(:close)

        instance.close
      end
    end
  end

  describe '#closed?' do
    it 'should delegate to net-ssh' do
      expect(@mock_ssh_conn).to receive(:closed?)

      instance.closed?
    end
  end

  describe '#desc' do
    it 'should include the host connected to' do
      expect(instance.desc).to include('test.example.com')
    end

    context 'when using a proxy host' do
      before(:each) do
        @proxy = double(:ssh_proxy, command_line: "ssh proxy.example.com arg1 arg2")
        instance.instance_variable_set(:@proxy, @proxy)
      end

      it 'should include the proxy host' do
        expect(instance.desc).to include('proxy.example.com')
      end
    end
  end
end
