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
      expect(instance.instance_variable_get('@arg_opts').to_s).to include(':hosts')
    end

    it 'should add --env to arg_opts' do
      expect(instance.instance_variable_get('@arg_opts').to_s).to include(':env')
    end

    it 'should persist options' do
      instance = Harrison::Deploy.new(testopt: 'foo')

      expect(instance.instance_variable_get('@options')).to include(testopt: 'foo')
    end
  end

  describe 'instance methods' do
    describe '#parse' do
      it 'should require an artifact to be passed in ARGV' do
        output = capture(:stderr) do
          expect(lambda { instance.parse(%w(deploy)) }).to exit_with_code(1)
        end

        expect(output).to include('must', 'specify', 'artifact')
      end

      it 'should use "base_dir" from Harrisonfile if present' do
        instance.parse(%w(deploy test_artifact.tar.gz))

        expect(instance.options).to include({ base_dir: '/hf_basedir' })
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

          expect(instance.instance_variable_get("@run_block")).to be test_block
        end
      end

      context 'when not passed a block' do
        before(:each) do
          @mock_ssh = double(:ssh, host: 'test_host1', exec: '', upload: true, download: true)
          allow(instance).to receive(:ssh).and_return(@mock_ssh)

          instance.instance_variable_set(:@run_block, Proc.new { |h| "block for #{h.host}" })
        end

        it 'should use hosts from --hosts if passed' do
          instance.instance_variable_set(:@_argv_hosts, [ 'argv_host1', 'argv_host2' ])

          output = capture(:stdout) do
            instance.run
          end

          expect(instance.hosts).to eq([ 'argv_host1', 'argv_host2' ])
          expect(output).to include('argv_host1', 'argv_host2')
          expect(output).to_not include('hf_host')
        end

        it 'should use hosts from Harrisonfile if --hosts not passed' do
          output = capture(:stdout) do
            instance.run
          end

          expect(instance.hosts).to eq([ 'hf_host' ])
          expect(output).to include('hf_host')
        end

        it 'should require hosts to be set somehow' do
          instance.hosts = nil

          output = capture(:stderr) do
            expect(lambda { instance.run }).to exit_with_code(1)
          end

          expect(output).to include('must', 'specify', 'hosts')
        end

        it 'should invoke the previously stored block once for each host' do
          instance.hosts = [ 'host1', 'host2', 'host3' ]

          output = capture(:stdout) do
            expect { |b| instance.run(&b); instance.run }.to yield_control.exactly(3).times
          end

          expect(output).to include('host1', 'host2', 'host3')
        end

        it 'should clean up old releases if passed a --keep option' do
          instance.keep = 3

          expect(instance).to receive(:cleanup_deploys).with(3)
          expect(instance).to receive(:cleanup_releases)

          output = capture(:stdout) do
            instance.run
          end
        end

        context 'when deploying from a remote artifact source' do
          before(:each) do
            instance.artifact = 'test_user@test_host1:/tmp/test_artifact.tar.gz'
          end

          it 'should invoke scp on the remote host' do
            allow(instance).to receive(:remote_exec).and_return('')
            expect(instance).to receive(:remote_exec).with(/scp test_user@test_host1:\/tmp\/test_artifact.tar.gz/).and_return('')

            output = capture(:stdout) do
              instance.run
            end

            expect(output).to include('deployed', 'test_user', 'test_host1', '/tmp/test_artifact.tar.gz')
          end

          it 'should not invoke Harrison::SSH.upload' do
            expect(@mock_ssh).not_to receive(:upload)

            output = capture(:stdout) do
              instance.run
            end

            expect(output).to include('deployed', 'test_user', 'test_host1', '/tmp/test_artifact.tar.gz')
          end
        end
      end
    end

    describe '#cleanup_deploys' do
      before(:each) do
        allow(instance).to receive(:deploys).and_return([ 'deploy_1', 'deploy_2', 'deploy_3', 'deploy_4', 'deploy_5' ])
      end

      it 'should remove deploys beyond the passed in limit' do
        expect(instance).to receive(:remote_exec).with(/rm -f deploy_2/).and_return('')
        expect(instance).to receive(:remote_exec).with(/rm -f deploy_1/).and_return('')

        output = capture(:stdout) do
          instance.cleanup_deploys(3)
        end

        expect(output).to include('purging', 'deploys', 'keeping 3')
      end
    end

    describe '#cleanup_releases' do
      before(:each) do
        allow(instance).to receive(:releases).and_return([ 'release_1', 'release_2', 'release_3', 'release_4', 'release_5' ])
        allow(instance).to receive(:active_releases).and_return([ 'release_3', 'release_4', 'release_5' ])
      end

      it 'should remove inactive releases' do
        expect(instance).to receive(:remote_exec).with(/rm -rf release_1/).and_return('')
        expect(instance).to receive(:remote_exec).with(/rm -rf release_2/).and_return('')

        capture(:stdout) do
          instance.cleanup_releases
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

        expect(instance.send(:ssh)).to be mock_ssh
      end

      it 'should reuse an existing connection to self.host' do
        mock_ssh = double(:ssh)
        instance.instance_variable_set(:@_conns, { test_host2: mock_ssh })

        instance.host = :test_host2

        expect(instance.send(:ssh)).to be mock_ssh
      end
    end

    describe '#remote_project_dir' do
      it 'should combine base_dir and project name' do
        instance.base_dir = '/test_base_dir'
        instance.project = 'test_project'

        expect(instance.send(:remote_project_dir)).to include('/test_base_dir', 'test_project')
      end
    end

    describe '#deploys' do
      it 'should invoke ls in the correct directory on the remote server' do
        expect(instance).to receive(:remote_exec).with(/deploys.*ls -1/).and_return('')

        instance.send(:deploys)
      end

      it 'should return an array of deploys' do
        expect(instance).to receive(:remote_exec).and_return("deploy_1\ndeploy_2\ndeploy_3\n")

        deploys = instance.send(:deploys)

        expect(deploys).to respond_to(:size)
        expect(deploys.size).to be 3
      end
    end

    describe '#releases' do
      it 'should invoke ls in the correct directory on the remote server' do
        expect(instance).to receive(:remote_exec).with(/releases.*ls -1/).and_return('')

        instance.send(:releases)
      end

      it 'should return an array of releases' do
        expect(instance).to receive(:remote_exec).and_return("release_1\nrelease_2\nrelease_3\n")

        releases = instance.send(:releases)

        expect(releases).to respond_to(:size)
        expect(releases.size).to be 3
      end
    end

    describe '#active_releases' do
      before(:each) do
        allow(instance).to receive(:remote_exec).with(/readlink/) do |cmd|
          "release_" + /`readlink deploy_([0-9]+)`/.match(cmd).captures[0]
        end
      end

      it 'should return an array of releases' do
        expect(instance).to receive(:deploys).and_return([ 'deploy_3', 'deploy_4', 'deploy_5' ])

        active_releases = instance.send(:active_releases)

        expect(active_releases).to respond_to(:size)
        expect(active_releases.size).to be 3
      end

      it 'should only return distinct releases' do
        expect(instance).to receive(:deploys).and_return([ 'deploy_3', 'deploy_4', 'deploy_5', 'deploy_3' ])

        active_releases = instance.send(:active_releases)

        expect(active_releases.size).to be 3
      end

      it 'should return releases corresponding to given deploys' do
        expect(instance).to receive(:deploys).and_return([ 'deploy_3' ])

        active_releases = instance.send(:active_releases)

        expect(active_releases).to include('release_3')
      end
    end
  end
end
