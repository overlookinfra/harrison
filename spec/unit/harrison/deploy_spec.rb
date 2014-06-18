require 'spec_helper'

describe Harrison::Deploy do
  let(:instance) do
    Harrison::Deploy.new.tap do |d|
      d.hosts = [ 'hf_host' ]
      d.base_dir = '/hf_basedir'
    end
  end

  describe '.initialize' do
    it 'should add --hosts to arg_opts' do
      instance.instance_variable_get('@arg_opts').to_s.should include(':hosts')
    end

    it 'should add --env to arg_opts' do
      instance.instance_variable_get('@arg_opts').to_s.should include(':env')
    end

    it 'should persist options' do
      instance = Harrison::Deploy.new(testopt: 'foo')

      instance.instance_variable_get('@options').should include(testopt: 'foo')
    end
  end

  describe 'instance methods' do
    describe '#parse' do
      it 'should use hosts from --hosts if passed' do
        instance.parse(%w(deploy test_artifact.tar.gz --hosts test1 test2 test3))

        instance.options.should include({ hosts: [ 'test1', 'test2', 'test3' ] })
      end

      it 'should use hosts from Harrisonfile if --hosts not passed' do
        instance.parse(%w(deploy test_artifact.tar.gz))

        instance.options.should include({ hosts: [ 'hf_host' ] })
      end

      it 'should require hosts to be set somehow' do
        instance.hosts = nil

        output = capture(:stderr) do
          lambda { instance.parse(%w(deploy test_artifact.tar.gz)) }.should exit_with_code(1)
        end

        output.should include('must', 'specify', 'hosts')
      end

      it 'should require an artifact to be passed in ARGV' do
        output = capture(:stderr) do
          lambda { instance.parse(%w(deploy)) }.should exit_with_code(1)
        end

        output.should include('must', 'specify', 'artifact')
      end

      it 'should use "base_dir" from Harrisonfile if present' do
        instance.parse(%w(deploy test_artifact.tar.gz))

        instance.options.should include({ base_dir: '/hf_basedir' })
      end

      it 'should default "base_dir" to "/opt"' do
        instance.base_dir = nil
        instance.parse(%w(deploy test_artifact.tar.gz))

        instance.options.should include({ base_dir: '/opt' })
      end
    end

    describe '#remote_exec' do
      before(:each) do
        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should prepend project dir onto passed command' do
        instance.base_dir = '/opt'
        instance.project = 'test_project'

        expect(@mock_ssh).to receive(:exec).with("cd /opt/test_project && test_command").and_return('')

        instance.remote_exec("test_command")
      end
    end

    describe '#run' do
      before(:each) do
        instance.artifact = 'test_artifact.tar.gz'
        instance.project = 'test_project'
      end

      context 'when passed a block' do
        it 'should store the block' do
          test_block = Proc.new { |test| "block_output" }
          instance.run(&test_block)

          instance.instance_variable_get("@run_block").should == test_block
        end
      end

      context 'when not passed a block' do
        before(:each) do
          @mock_ssh = double(:ssh, exec: '', upload: true, download: true)
          expect(instance).to receive(:ssh).at_least(:once).and_return(@mock_ssh)
        end

        it 'should invoke the previously stored block once for each host' do
          instance.hosts = [ 'host1', 'host2', 'host3' ]

          test_block = Proc.new { |test| puts "block for #{test.host}" }
          instance.run(&test_block)

          output = capture(:stdout) do
            instance.run
          end

          output.should include('block for host1', 'block for host2', 'block for host3')
        end
      end
    end

    describe '#close' do
      before(:each) do
        @test_host1_ssh = double(:ssh, 'closed?' => false)
        @test_host2_ssh = double(:ssh, 'closed?' => false)

        instance.instance_variable_set(:@_conns, { test_host1: @test_host1_ssh, test_host2: @test_host2_ssh })
      end

      context 'when passed a specific host' do
        it 'should close the connection to that host' do
          expect(@test_host1_ssh).to receive(:close).and_return(true)

          instance.close(:test_host1)
        end
      end

      it 'should close every open ssh connection' do
        expect(@test_host1_ssh).to receive(:close).and_return(true)
        expect(@test_host2_ssh).to receive(:close).and_return(true)

        instance.close
      end
    end
  end

  describe 'protected methods' do
    describe '#ssh' do
      it 'should open a new SSH connection to self.host' do
        mock_ssh = double(:ssh)
        expect(Harrison::SSH).to receive(:new).and_return(mock_ssh)

        instance.host = 'test_host'

        instance.send(:ssh).should == mock_ssh
      end

      it 'should reuse an existing connection to self.host' do
        mock_ssh = double(:ssh)
        instance.instance_variable_set(:@_conns, { test_host2: mock_ssh })

        instance.host = :test_host2

        instance.send(:ssh).should == mock_ssh
      end
    end

    describe '#remote_project_dir' do
      it 'should combine base_dir and project name' do
        instance.base_dir = '/test_base_dir'
        instance.project = 'test_project'

        instance.send(:remote_project_dir).should include('/test_base_dir', 'test_project')
      end
    end
  end
end
