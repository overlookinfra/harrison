require 'spec_helper'

describe Harrison::Deploy do
  before(:all) do
    Harrison.class_variable_set(:@@config, Harrison::Config.new)
    Harrison.config.project = 'test_project'
  end

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

    it 'should set up default phases' do
      expect(instance.instance_variable_get(:@_phases)).to_not be_empty
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

    describe '#add_phase' do
      before(:each) do
        allow(Harrison::Deploy::Phase).to receive(:new).with(anything)
      end

      it 'should instantiate a new Phase object with the given name' do
        expect(Harrison::Deploy::Phase).to receive(:new).with(:test)

        instance.add_phase(:test)
      end

      it 'should pass a given block to the Phase object constructor' do
        @mock_phase = double(:phase)

        expect(Harrison::Deploy::Phase).to receive(:new).with(:test).and_yield(@mock_phase)
        expect(@mock_phase).to receive(:in_block)

        instance.add_phase :test do |p|
          p.in_block
        end
      end
    end

    describe '#remote_exec' do
      before(:each) do
        instance.base_dir = '/opt'

        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should prepend project dir onto passed command' do
        expect(@mock_ssh).to receive(:exec).with("cd /opt/test_project && test_command").and_return('')

        instance.remote_exec("test_command")
      end
    end

    describe '#current_symlink' do
      it 'starts at base_dir' do
        expect(instance.current_symlink).to match(/^#{instance.base_dir}/)
      end

      it 'is not just base_dir' do
        expect(instance.current_symlink).to_not equal(instance.base_dir)
      end
    end

    describe '#update_current_symlink' do
      before(:each) do
        instance.deploy_link = 'new_deploy'

        allow(instance).to receive(:remote_exec).with(/^ln/)
      end

      context 'current_symlink already exists' do
        before(:each) do
          expect(instance).to receive(:remote_exec).with(/readlink/).and_return('old_link_target')
        end

        it 'should store old symlink target' do
          instance.update_current_symlink

          expect(instance.instance_variable_get(:@_old_current)).to_not be_nil
        end

        it 'should replace existing symlink' do
          expect(instance).to receive(:remote_exec).with(/^ln .* #{instance.deploy_link}/)

          instance.update_current_symlink
        end
      end

      context 'current_symlink does not exist yet' do
        before(:each) do
          expect(instance).to receive(:remote_exec).with(/readlink/).and_return('')
        end

        it 'should not store old symlink target' do
          instance.update_current_symlink

          expect(instance.instance_variable_get(:@_old_current)).to be_nil
        end

        it 'should create symlink' do
          expect(instance).to receive(:remote_exec).with(/^ln .* #{instance.deploy_link}/)

          instance.update_current_symlink
        end
      end
    end

    describe '#revert_current_symlink' do
      it 'should set link back to old target if old target is set' do
        instance.instance_variable_set(:@_old_current, 'old_link_target')

        expect(instance).to receive(:remote_exec).with(/^ln .* old_link_target/)

        instance.revert_current_symlink
      end

      it 'should be a no-op if old target is not set' do
        expect(instance).to_not receive(:remote_exec)

        instance.revert_current_symlink
      end
    end

    describe '#run' do
      before(:each) do
        instance.artifact = 'test_artifact.tar.gz'

        @mock_ssh = double(:ssh, host: 'test_host1', exec: '', upload: true, download: true)
        allow(instance).to receive(:ssh).and_return(@mock_ssh)
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

      it 'should run the specified phases once for each host' do
        instance.hosts = [ 'host1', 'host2', 'host3' ]

        mock_phase = double(:phase, matches_context?: true)
        expect(Harrison::Deploy::Phase).to receive(:new).with(:test).and_return(mock_phase)
        instance.add_phase :test
        instance.phases = [ :test ]

        expect(mock_phase).to receive(:_run).exactly(3).times

        output = capture(:stdout) do
          instance.run
        end

        expect(output).to include('host1', 'host2', 'host3')
      end

      context 'when a deployment phase fails on a host' do
        before(:each) do
          @upload   = double(:phase, name: :upload, matches_context?: true, _run: true, _fail: true)
          @extract  = double(:phase, name: :extract, matches_context?: true, _run: true, _fail: true)
          @link     = double(:phase, name: :link, matches_context?: true)

          allow(@link).to receive(:_run).and_throw(:failure, true)

          instance.instance_variable_set(:@_phases, {
            upload:   @upload,
            extract:  @extract,
            link:     @link,
          })

          instance.phases = [ :upload, :extract, :link ]

          instance.hosts = [ 'host1', 'host2', 'host3' ]
        end

        it "should invoke on_fail block for completed phases on each host" do
          expect(@extract).to receive(:_fail).exactly(3).times.ordered
          expect(@upload).to receive(:_fail).exactly(3).times.ordered

          capture([ :stdout, :stderr ]) do
            expect(lambda { instance.run }).to exit_with_code(1)
          end
        end

        it "should invoke on_fail block on each host in reverse order" do
          expect(@extract).to receive(:_fail) { |context| expect(context.host).to eq('host3') }.ordered
          expect(@extract).to receive(:_fail) { |context| expect(context.host).to eq('host2') }.ordered
          expect(@extract).to receive(:_fail) { |context| expect(context.host).to eq('host1') }.ordered

          capture([ :stdout, :stderr ]) do
            expect(lambda { instance.run }).to exit_with_code(1)
          end
        end
      end

      context 'when invoked via rollback' do
        before(:each) do
          instance.rollback = true

          @mock_ssh = double(:ssh, host: 'test_host1', exec: '', upload: true, download: true)
          allow(instance).to receive(:ssh).and_return(@mock_ssh)
        end

        it 'should find the release of the previous deploy' do
          expect(instance).to receive(:deploys).and_return([ 'deploy_1', 'deploy_2', 'deploy_3', 'deploy_4', 'deploy_5' ])
          expect(@mock_ssh).to receive(:exec).with(/readlink .* deploy_4/)

          capture(:stdout) do
            instance.run
          end
        end

        it 'should not run :upload, :extract, or :cleanup phases' do
          expect(instance).to receive(:deploys).and_return([ 'deploy_1', 'deploy_2', 'deploy_3', 'deploy_4', 'deploy_5' ])
          expect(@mock_ssh).to receive(:exec).with(/readlink .* deploy_4/).and_return('old_release')

          disabled_phase = double(:phase)
          expect(disabled_phase).to_not receive(:_run)

          enabled_phase = double(:phase, matches_context?: true)
          expect(enabled_phase).to receive(:_run)

          instance.instance_variable_set(:@_phases, {
            upload:   disabled_phase,
            extract:  disabled_phase,
            link:     enabled_phase,
            cleanup:  disabled_phase,
          })

          capture(:stdout) do
            instance.run
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
    describe '#add_default_phases' do
      it 'should add each default phase' do
        # Trigger constructor invocations so we can only count new invocation below.
        instance

        expect(Harrison::Deploy::Phase).to receive(:new).with(:upload)
        expect(Harrison::Deploy::Phase).to receive(:new).with(:extract)
        expect(Harrison::Deploy::Phase).to receive(:new).with(:link)
        expect(Harrison::Deploy::Phase).to receive(:new).with(:cleanup)

        instance.send(:add_default_phases)
      end
    end

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

  describe 'default phases' do
    before(:each) do
      instance.artifact = '/tmp/test_artifact.tar.gz'

      @mock_ssh = double(:ssh, host: 'test_host1', exec: '', upload: true, download: true)
      allow(instance).to receive(:ssh).and_return(@mock_ssh)
    end

    describe 'upload' do
      before(:each) do
        @phase = instance.instance_variable_get(:@_phases)[:upload]
      end

      describe 'on_run' do
        context 'when deploying from a local artifact' do
          it 'should invoke Harrison::SSH.upload' do
            expect(@mock_ssh).to receive(:upload).with(/test_artifact\.tar\.gz/, anything)

            capture(:stdout) do
              @phase._run(instance)
            end
          end
        end

        context 'when deploying from a remote artifact' do
          before(:each) do
            instance.artifact = 'test_user@test_host1:/tmp/test_artifact.tar.gz'
          end

          it 'should invoke scp on the remote host' do
            allow(instance).to receive(:remote_exec).and_return('')
            expect(instance).to receive(:remote_exec).with(/scp test_user@test_host1:\/tmp\/test_artifact.tar.gz/).and_return('')

            capture(:stdout) do
              @phase._run(instance)
            end
          end

          it 'should not invoke Harrison::SSH.upload' do
            expect(@mock_ssh).not_to receive(:upload)

            capture(:stdout) do
              @phase._run(instance)
            end
          end
        end
      end

      describe 'on_fail' do
        it 'should remove uploaded artifact' do
          expect(instance).to receive(:remote_exec).with(/rm.*test_artifact\.tar\.gz/)

          capture(:stdout) do
            @phase._fail(instance)
          end
        end
      end
    end

    describe 'extract' do
      before(:each) do
        @phase = instance.instance_variable_get(:@_phases)[:extract]
      end

      describe 'on_run' do
        it 'should untar the artifact and then remove it' do
          allow(instance).to receive(:remote_exec)
          expect(instance).to receive(:remote_exec).with(/tar.*test_artifact\.tar\.gz/).ordered
          expect(instance).to receive(:remote_exec).with(/rm.*test_artifact\.tar\.gz/).ordered

          capture(:stdout) do
            @phase._run(instance)
          end
        end
      end

      describe 'on_fail' do
        it 'should remove the extracted release' do
          expect(instance).to receive(:remote_exec).with(/rm.*#{instance.release_dir}/)

          capture(:stdout) do
            @phase._fail(instance)
          end
        end
      end
    end

    describe 'link' do
      before(:each) do
        @phase = instance.instance_variable_get(:@_phases)[:link]
      end

      describe 'on_run' do
        it 'should create a new deploy link' do
          expect(instance).to receive(:remote_exec).with(/ln.*#{instance.release_dir}.*#{instance.deploy_link}/)

          capture(:stdout) do
            @phase._run(instance)
          end
        end
      end

      describe 'on_fail' do
        it 'should remove deploy link' do
          expect(instance).to receive(:remote_exec).with(/rm.*#{instance.deploy_link}/)

          capture(:stdout) do
            @phase._fail(instance)
          end
        end
      end
    end

    describe 'cleanup' do
      before(:each) do
        @phase = instance.instance_variable_get(:@_phases)[:cleanup]
      end

      describe 'on_run' do
        it 'should clean up old releases if passed a --keep option' do
          instance.keep = 3

          expect(instance).to receive(:cleanup_deploys).with(3)
          expect(instance).to receive(:cleanup_releases)

          capture(:stdout) do
            @phase._run(instance)
          end
        end
      end

      describe 'on_fail' do
        it 'should not do anything' do
          expect(instance).to_not receive(:remote_exec)

          capture(:stdout) do
            @phase._fail(instance)
          end
        end
      end
    end
  end
end
