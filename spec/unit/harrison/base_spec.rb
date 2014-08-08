require 'spec_helper'

describe Harrison::Base do
  let(:instance) { Harrison::Base.new }

  describe 'initialize' do
    it 'should persist arg_opts' do
      instance = Harrison::Base.new(['foo'])

      expect(instance.instance_variable_get('@arg_opts')).to include('foo')
    end

    it 'should add debug to arg_opts' do
      expect(instance.instance_variable_get('@arg_opts').to_s).to include(':debug')
    end

    it 'should persist options' do
      instance = Harrison::Base.new([], testopt: 'foo')

      expect(instance.instance_variable_get('@options')).to include(testopt: 'foo')
    end
  end

  describe 'class methods' do
    describe '.option_helper' do
      it 'should define a getter instance method for the option' do
        Harrison::Base.option_helper('foo')

        expect(instance.methods).to include(:foo)
      end

      it 'should define a setter instance method for the option' do
        Harrison::Base.option_helper('foo')

        expect(instance.methods).to include(:foo=)
      end
    end
  end

  describe 'instance methods' do
    describe '#exec' do
      it 'should execute a command locally and return the output' do
        expect(instance.exec('echo "foo"')).to eq('foo')
      end

      it 'should complain if command returns non-zero' do
        output = capture(:stderr) do
          expect(lambda { instance.exec('cat noexist 2>/dev/null') }).to exit_with_code(1)
        end

        expect(output).to include('unable', 'execute', 'local', 'command')
      end
    end

    describe '#remote_exec' do
      before(:each) do
        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should delegate command to ssh instance' do
        expect(@mock_ssh).to receive(:exec).and_return('remote_exec_return')

        expect(instance.remote_exec('remote exec')).to eq('remote_exec_return')
      end

      it 'should complain if command returns nil' do
        expect(@mock_ssh).to receive(:exec).and_return(nil)

        output = capture(:stderr) do
          expect(lambda { instance.remote_exec('remote exec fail') }).to exit_with_code(1)
        end

        expect(output).to include('unable', 'execute', 'remote', 'command')
      end
    end

    describe '#parse' do
      before(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
      end

      after(:each) do
        Harrison.send(:remove_const, "DEBUG") if Harrison.const_defined?("DEBUG")
      end

      it 'should recognize options from the command line' do
        instance = Harrison::Base.new([
          [ :testopt, "Test option.", :type => :string ]
        ])

        instance.parse(%w(test --testopt foozle))

        expect(instance.options).to include({testopt: 'foozle'})
      end

      it 'should set the debug flag on the module when passed --debug' do
        instance.parse(%w(test --debug))

        expect(Harrison::DEBUG).to be true
      end
    end

    describe '#run' do
      context 'when given a block' do
        it 'should store the block' do
          test_block = Proc.new { |test| "block_output" }
          instance.run(&test_block)

          expect(instance.instance_variable_get("@run_block")).to eq(test_block)
        end
      end

      context 'when not given a block' do
        it 'should return nil if no block stored' do
          expect(instance.run).to be_nil
        end

        it 'should invoke the previously stored block if it exists' do
          test_block = Proc.new { |test| "block_output" }
          instance.run(&test_block)

          expect(instance.run).to eq("block_output")
        end
      end
    end

    describe '#download' do
      before(:each) do
        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should delegate downloads to the SSH class' do
        expect(@mock_ssh).to receive(:download).with('remote', 'local')

        instance.download('remote', 'local')
      end
    end

    describe '#upload' do
      before(:each) do
        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should delegate uploads to the SSH class' do
        expect(@mock_ssh).to receive(:upload).with('local', 'remote')

        instance.upload('local', 'remote')
      end
    end

    describe '#close' do
      before(:each) do
        @mock_ssh = double(:ssh)
        instance.instance_variable_set('@ssh', @mock_ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should invoke close on ssh instance' do
        expect(@mock_ssh).to receive(:close)

        instance.close
      end
    end
  end

  describe 'protected methods' do
    describe '#ssh' do
      it 'should instantiate a new ssh instance if needed' do
        mock_ssh = double(:ssh)
        expect(Harrison::SSH).to receive(:new).and_return(mock_ssh)

        expect(instance.send(:ssh)).to be mock_ssh
      end

      it 'should return previously instantiated ssh instance' do
        mock_ssh = double(:ssh)
        instance.instance_variable_set('@ssh', mock_ssh)
        expect(Harrison::SSH).to_not receive(:new)

        expect(instance.send(:ssh)).to be mock_ssh
      end
    end

    describe '#remote_regex' do
      it 'should match a standard remote SCP target without a username' do
        expect(instance.send(:remote_regex)).to match("test_host1:/tmp/target")
      end

      it 'should match a standard remote SCP target with a username' do
        expect(instance.send(:remote_regex)).to match("testuser@test_host:/tmp/target")
      end

      it 'should not match a local file path' do
        expect(instance.send(:remote_regex)).not_to match("tmp/target")
      end
    end

    describe '#ensure_local_dir' do
      it 'should try to create a directory locally' do
        expect(instance).to receive(:system).with(/local_dir/).and_return(true)

        expect(instance.send(:ensure_local_dir, 'local_dir')).to be true
      end

      it 'should only try to create a directory once' do
        expect(instance).to receive(:system).with(/local_dir/).once.and_return(true)

        expect(instance.send(:ensure_local_dir, 'local_dir')).to be true
        expect(instance.send(:ensure_local_dir, 'local_dir')).to be true
      end
    end

    describe '#ensure_remote_dir' do
      before(:each) do
        @mock_ssh = double(:ssh, host: 'test_host1')
        @mock_ssh2 = double(:ssh, host: 'test_host2')

        allow(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should try to create a directory remotely' do
        expect(@mock_ssh).to receive(:exec).with(/remote_dir/).and_return(true)
        expect(instance.send(:ensure_remote_dir, 'remote_dir')).to be true
      end

      it 'should try to create a directory once for each distinct ssh connection' do
        expect(@mock_ssh).to receive(:exec).with(/remote_dir/).once.and_return(true)
        expect(@mock_ssh2).to receive(:exec).with(/remote_dir/).once.and_return(true)

        expect(instance.send(:ensure_remote_dir, 'remote_dir')).to be true
        expect(instance.send(:ensure_remote_dir, 'remote_dir', @mock_ssh2)).to be true
      end

      it 'should only try to create a directory once for the same ssh connection' do
        expect(@mock_ssh).to receive(:exec).with(/remote_dir/).once.and_return(true)

        expect(instance.send(:ensure_remote_dir, 'remote_dir')).to be true
        expect(instance.send(:ensure_remote_dir, 'remote_dir')).to be true
      end
    end
  end
end
