require 'spec_helper'

describe Harrison do
  describe '.invoke' do
    it 'should exit when no args are passed' do
      output = capture(:stderr) do
        lambda { Harrison.invoke([]) }.should exit_with_code(1)
      end

      output.should include('no', 'command', 'given')
    end

    it 'should output base help when first arg is --help' do
      output = capture(:stdout) do
        lambda { Harrison.invoke(['--help']) }.should exit_with_code(0)
      end

      output.should include('options', 'debug', 'help')
    end

    it 'should look for a Harrisonfile' do
      expect(Harrison).to receive(:find_harrisonfile).and_return(harrisonfile_fixture_path(:valid))

      output = capture(:stderr) do
        lambda { Harrison.invoke(['test']) }.should exit_with_code(1)
      end

      output.should include('unrecognized', 'command', 'test')
    end

    it 'should complain if unable to find a Harrisonfile' do
      expect(Harrison).to receive(:find_harrisonfile).and_return(nil)

      output = capture(:stderr) do
        lambda { Harrison.invoke(['test']) }.should exit_with_code(1)
      end

      output.should include('could', 'not', 'find', 'harrisonfile')
    end

    it 'should eval Harrisonfile' do
      expect(Harrison).to receive(:find_harrisonfile).and_return(harrisonfile_fixture_path(:valid))
      expect(Harrison).to receive(:eval_script).with(harrisonfile_fixture_path(:valid))

      output = capture(:stderr) do
        lambda { Harrison.invoke(['test']) }.should exit_with_code(1)
      end

      output.should include('unrecognized', 'command', 'test')
    end
  end

  describe '.config' do
    pending
  end

  describe '.package' do
    pending
  end

  describe '.deploy' do
    pending
  end

  context 'private methods' do
    describe '.find_harrisonfile' do
      pending
    end

    describe '.eval_script' do
      pending
    end
  end
end
