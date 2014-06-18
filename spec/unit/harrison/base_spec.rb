require 'spec_helper'

describe Harrison::Base do
  let(:instance) { Harrison::Base.new }

  describe 'initialize' do
    it 'should persist arg_opts' do
      instance = Harrison::Base.new(['foo'])

      instance.instance_variable_get('@arg_opts').should include('foo')
    end

    it 'should add debug to arg_opts' do
      instance.instance_variable_get('@arg_opts').to_s.should include(':debug')
    end

    it 'should persist options' do
      instance = Harrison::Base.new([], testopt: 'foo')

      instance.instance_variable_get('@options').should include(testopt: 'foo')
    end
  end

  describe 'class methods' do
    describe '.option_helper' do
      it 'should define a getter instance method for the option' do
        Harrison::Base.option_helper('foo')

        instance.methods.should include(:foo)
      end

      it 'should define a setter instance method for the option' do
        Harrison::Base.option_helper('foo')

        instance.methods.should include(:foo=)
      end
    end
  end

  describe 'instance methods' do
    describe '#exec' do
      it 'should execute a command locally and return the output' do
        instance.exec('echo "foo"').should == 'foo'
      end

      it 'should complain if command returns non-zero' do
        output = capture(:stderr) do
          lambda { instance.exec('cat noexist 2>/dev/null') }.should exit_with_code(1)
        end

        output.should include('unable', 'execute', 'local', 'command')
      end
    end

    describe '#remote_exec' do
      before(:each) do
        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should delegate command to ssh instance' do
        expect(@mock_ssh).to receive(:exec).and_return('remote_exec_return')

        instance.remote_exec('remote exec').should == 'remote_exec_return'
      end

      it 'should complain if command returns nil' do
        expect(@mock_ssh).to receive(:exec).and_return(nil)

        output = capture(:stderr) do
          lambda { instance.remote_exec('remote exec fail') }.should exit_with_code(1)
        end

        output.should include('unable', 'execute', 'remote', 'command')
      end
    end

    describe '#parse' do
      it 'should recognize options from the command line' do
        instance = Harrison::Base.new([
          [ :testopt, "Test option.", :type => :string ]
        ])

        instance.parse(%w(test --testopt foozle))

        instance.options.should include({testopt: 'foozle'})
      end

      it 'should set the debug flag on the module when passed --debug' do
        instance.parse(%w(test --debug))

        Harrison::DEBUG.should be_true
      end
    end

    describe '#run' do
      context 'when given a block' do
        it 'should store the block' do
          test_block = Proc.new { |test| "block_output" }
          instance.run(&test_block)

          instance.instance_variable_get("@run_block").should == test_block
        end
      end

      context 'when not given a block' do
        it 'should return nil if no block stored' do
          instance.run.should == nil
        end

        it 'should invoke the previously stored block if it exists' do
          test_block = Proc.new { |test| "block_output" }
          instance.run(&test_block)

          instance.run.should == "block_output"
        end
      end
    end

    describe '#download' do
      before(:each) do
        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should delegate downloads to the SSH class' do
        expect(@mock_ssh).to receive(:download).with('remote', 'local').and_return(true)

        instance.download('remote', 'local').should == true
      end
    end

    describe '#upload' do
      before(:each) do
        @mock_ssh = double(:ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should delegate uploads to the SSH class' do
        expect(@mock_ssh).to receive(:upload).with('local', 'remote').and_return(true)

        instance.upload('local', 'remote').should == true
      end
    end

    describe '#close' do
      before(:each) do
        @mock_ssh = double(:ssh)
        instance.instance_variable_set('@ssh', @mock_ssh)
        expect(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should invoke close on ssh instance' do
        expect(@mock_ssh).to receive(:close).and_return(true)

        instance.close.should == true
      end
    end
  end

  describe 'protected methods' do
    describe '#ssh' do
      it 'should instantiate a new ssh instance if needed' do
        mock_ssh = double(:ssh)
        expect(Harrison::SSH).to receive(:new).and_return(mock_ssh)

        instance.send(:ssh).should == mock_ssh
      end

      it 'should return previously instantiated ssh instance' do
        mock_ssh = double(:ssh)
        instance.instance_variable_set('@ssh', mock_ssh)
        expect(Harrison::SSH).to_not receive(:new)

        instance.send(:ssh).should == mock_ssh
      end
    end

    describe '#ensure_local_dir' do
      it 'should try to create a directory locally' do
        expect(instance).to receive(:system).with(/local_dir/).and_return(true)

        instance.send(:ensure_local_dir, 'local_dir').should == true
      end

      it 'should only try to create a directory once' do
        expect(instance).to receive(:system).with(/local_dir/).once.and_return(true)

        instance.send(:ensure_local_dir, 'local_dir').should == true
        instance.send(:ensure_local_dir, 'local_dir').should == true
      end
    end

    describe '#ensure_remote_dir' do
      before(:each) do
        @mock_ssh = double(:ssh)
        allow(instance).to receive(:ssh).and_return(@mock_ssh)
      end

      it 'should try to create a directory remotely' do
        expect(@mock_ssh).to receive(:exec).with(/remote_dir/).and_return(true)

        instance.send(:ensure_remote_dir, 'testhost', 'remote_dir').should == true
      end

      it 'should try to create a directory once for each distinct host' do
        expect(@mock_ssh).to receive(:exec).with(/remote_dir/).twice.and_return(true)

        instance.send(:ensure_remote_dir, 'test-host', 'remote_dir').should == true
        instance.send(:ensure_remote_dir, 'another-host', 'remote_dir').should == true
      end

      it 'should only try to create a directory once for the same host' do
        expect(@mock_ssh).to receive(:exec).with(/remote_dir/).once.and_return(true)

        instance.send(:ensure_remote_dir, 'test-host', 'remote_dir').should == true
        instance.send(:ensure_remote_dir, 'test-host', 'remote_dir').should == true
      end
    end
  end
end
