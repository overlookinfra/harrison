require 'spec_helper'

describe Harrison::Package do
  let(:instance) do
    Harrison::Package.new.tap do |p|
      p.project = 'test_project'
      p.host = 'hf_host'
      p.commit = 'HEAD'
    end
  end

  describe '.initialize' do
    it 'should add --commit to arg_opts' do
      instance.instance_variable_get('@arg_opts').to_s.should include(':commit')
    end

    it 'should add --purge to arg_opts' do
      instance.instance_variable_get('@arg_opts').to_s.should include(':purge')
    end

    it 'should add --pkg-dir to arg_opts' do
      instance.instance_variable_get('@arg_opts').to_s.should include(':pkg_dir')
    end

    it 'should add --remote-dir to arg_opts' do
      instance.instance_variable_get('@arg_opts').to_s.should include(':remote_dir')
    end

    it 'should persist options' do
      instance = Harrison::Package.new(testopt: 'foo')

      instance.instance_variable_get('@options').should include(testopt: 'foo')
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
        instance.project = 'test_project'

        expect(@mock_ssh).to receive(:exec).with("cd ~/.harrison/test_project/package && test_command").and_return('')

        instance.remote_exec("test_command")
      end
    end

    describe '#run' do
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
          allow(instance).to receive(:ssh).at_least(:once).and_return(@mock_ssh)

          allow(instance).to receive(:ensure_local_dir).and_return(true)
          allow(instance).to receive(:resolve_commit!).and_return('test')
          allow(instance).to receive(:excludes_for_tar).and_return('')
        end

        it 'should invoke the previously stored block once with host' do
          test_block = Proc.new { |test| puts "block for #{test.host}" }
          instance.run(&test_block)

          output = capture(:stdout) do
            instance.run
          end

          output.should include('block for hf_host')
        end
      end
    end
  end

  describe 'protected methods' do
    describe '#remote_project_dir' do
      it 'should combine remote dir and project name' do
        instance.remote_dir = '~/.harrison'
        instance.project = 'test_project'

        instance.send(:remote_project_dir).should include('~/.harrison', 'test_project')
      end
    end

    describe '#resolve_commit!' do
      it 'should resolve commit reference to a short sha using git rev-parse' do
        instance.commit = 'giant'
        expect(instance).to receive(:exec).with(/git rev-parse.*giant/).and_return('fef1f0')

        instance.send(:resolve_commit!).should == 'fef1f0'
      end
    end

    describe '#excludes_for_tar' do
      it 'should return an empty string if exclude is nil' do
        instance.exclude = nil

        instance.send(:excludes_for_tar).should == ''
      end

      it 'should return an empty string if exclude is empty' do
        instance.exclude = []

        instance.send(:excludes_for_tar).should == ''
      end

      it 'should return an --exclude option for each member of exclude' do
        instance.exclude = [ 'fee', 'fi', 'fo', 'fum' ]

        instance.send(:excludes_for_tar).scan(/--exclude/).size.should == instance.exclude.size
      end
    end
  end
end
