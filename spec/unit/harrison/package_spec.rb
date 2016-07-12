require 'spec_helper'

describe Harrison::Package do
  before(:all) do
    Harrison.class_variable_set(:@@config, Harrison::Config.new)
    Harrison.config.project = 'test_project'
  end

  let(:instance) do
    Harrison::Package.new.tap do |p|
      p.host = 'hf_host'
      p.commit = 'HEAD'
    end
  end

  describe '.initialize' do
    it 'should add --commit to arg_opts' do
      expect(instance.instance_variable_get('@arg_opts').to_s).to include(':commit')
    end

    it 'should add --purge to arg_opts' do
      expect(instance.instance_variable_get('@arg_opts').to_s).to include(':purge')
    end

    it 'should add --destination to arg_opts' do
      expect(instance.instance_variable_get('@arg_opts').to_s).to include(':destination')
    end

    it 'should add --remote-dir to arg_opts' do
      expect(instance.instance_variable_get('@arg_opts').to_s).to include(':remote_dir')
    end

    it 'should persist options' do
      instance = Harrison::Package.new(testopt: 'foo')

      expect(instance.instance_variable_get('@options')).to include(testopt: 'foo')
    end
  end

  describe 'instance methods' do
    describe '#remote_exec' do
      before(:each) do
        @mock_ssh = double(:ssh)
        allow(instance).to receive(:ssh).and_return(@mock_ssh)
        allow(instance).to receive(:ensure_remote_dir).and_return(true)
      end

      it 'should prepend remote build dir onto passed command' do
        instance.remote_dir = '~/.harrison'

        expect(@mock_ssh).to receive(:exec).with("cd ~/.harrison/test_project/package && test_command").and_return('')

        instance.remote_exec("test_command")
      end
    end

    describe '#run' do
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
          allow(instance).to receive(:ssh).at_least(:once).and_return(@mock_ssh)

          allow(instance).to receive(:ensure_destination).and_return(true)
          allow(instance).to receive(:resolve_commit!).and_return('test')
          allow(instance).to receive(:excludes_for_tar).and_return('')
        end

        it 'should invoke the previously stored block once with host' do
          test_block = Proc.new { |test| puts "block for #{test.host}" }
          instance.run(&test_block)

          output = capture(:stdout) do
            instance.run
          end

          expect(output).to include('block for hf_host')
        end
      end
    end
  end

  describe 'protected methods' do
    describe '#remote_project_dir' do
      it 'should combine remote dir and project name' do
        instance.remote_dir = '~/.harrison'

        expect(instance.send(:remote_project_dir)).to include('~/.harrison', 'test_project')
      end
    end

    describe '#resolve_commit!' do
      it 'should resolve commit reference to a short sha using git rev-parse' do
        instance.commit = 'giant'
        expect(instance).to receive(:exec).with(/git rev-parse.*giant/).and_return('fef1f0')

        expect(instance.send(:resolve_commit!)).to eq('fef1f0')
      end
    end

    describe '#excludes_for_tar' do
      it 'should return an empty string if exclude is nil' do
        instance.exclude = nil

        expect(instance.send(:excludes_for_tar)).to be_empty
      end

      it 'should return an empty string if exclude is empty' do
        instance.exclude = []

        expect(instance.send(:excludes_for_tar)).to be_empty
      end

      it 'should return an --exclude option for each member of exclude' do
        instance.exclude = [ 'fee', 'fi', 'fo', 'fum' ]

        expect(instance.send(:excludes_for_tar).scan(/--exclude/).size).to eq(instance.exclude.size)
      end
    end

    describe '#ensure_destination' do
      it 'should ensure a local destination' do
        expect(instance).to receive(:ensure_local_dir).with('/tmp/test_path').and_return(true)

        instance.send(:ensure_destination, '/tmp/test_path')
      end

      it 'should ensure a remote destination' do
        mock_ssh = double(:ssh, host: 'test_host1')
        expect(mock_ssh).to receive(:exec).with(/\/tmp\/test_path/).and_return(true)
        expect(Harrison::SSH).to receive(:new).with({ host: 'test_host1', user: 'test_user' }).and_return(mock_ssh)

        instance.send(:ensure_destination, 'test_user@test_host1:/tmp/test_path')
      end
    end
  end
end
