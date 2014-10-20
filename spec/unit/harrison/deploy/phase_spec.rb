require 'spec_helper'

describe Harrison::Deploy::Phase do
  let(:instance) do
    Harrison::Deploy::Phase.new(:test_phase)
  end

  describe 'initialize' do
    it 'should set name' do
      expect(instance.name).to be :test_phase
    end

    it 'should yield itself to passed block' do
      expect { |b| Harrison::Deploy::Phase.new(:block_test, &b) }.to yield_with_args(Harrison::Deploy::Phase)
    end
  end

  describe 'instance methods' do
    describe '#add_condition' do
      it 'should accept and store a block' do
        instance.add_condition { |c| true }

        expect(instance.instance_variable_get(:@conditions).size).to be 1
      end
    end

    describe '#matches_context?' do
      it 'should pass the given context to each condition block' do
        mock_proc = double(:proc)
        instance.instance_variable_set(:@conditions, [ mock_proc ])

        mock_context = double(:context)

        expect(mock_proc).to receive(:call).with(mock_context)

        instance.matches_context?(mock_context)
      end

      it 'should be true if all conditions evaluate to true' do
        instance.instance_variable_set(:@conditions, [
          Proc.new { |c| true },
          Proc.new { |c| true },
          Proc.new { |c| true },
        ])

        expect(instance.matches_context?(double(:context))).to be true
      end

      it 'should be false if at least one condition evaluates to false' do
        instance.instance_variable_set(:@conditions, [
          Proc.new { |c| true },
          Proc.new { |c| false },
          Proc.new { |c| true },
        ])

        expect(instance.matches_context?(double(:context))).to be false
      end
    end

    describe '#on_run' do
      it 'should store the given block' do
        instance.on_run { |c| true }

        expect(instance.instance_variable_get(:@run_block)).to_not be_nil
      end
    end

    describe '#on_fail' do
      it 'should store the given block' do
        instance.on_fail { |c| true }

        expect(instance.instance_variable_get(:@fail_block)).to_not be_nil
      end
    end

    describe '#_run' do
      context 'context matches conditions' do
        before(:each) do
          allow(instance).to receive(:matches_context?).and_return(true)
        end

        it 'should invoke the previously stored block with given context' do
          mock_context = double(:context, host: 'test_host')

          mock_proc = double(:proc)
          instance.instance_variable_set(:@run_block, mock_proc)

          expect(mock_proc).to receive(:call).with(mock_context)

          capture(:stdout) do
            instance._run(mock_context)
          end
        end
      end

      context 'context does not match conditions' do
        before(:each) do
          allow(instance).to receive(:matches_context?).and_return(false)
        end

        it 'should not invoke the previously stored block' do
          mock_context = double(:context)

          mock_proc = double(:proc)
          instance.instance_variable_set(:@run_block, mock_proc)

          expect(mock_proc).to_not receive(:call)

          instance._run(mock_context)
        end
      end
    end

    describe '#_fail' do
      context 'context matches conditions' do
        before(:each) do
          allow(instance).to receive(:matches_context?).and_return(true)
        end

        it 'should invoke the previously stored block with given context' do
          mock_context = double(:context, host: 'test_host')

          mock_proc = double(:proc)
          instance.instance_variable_set(:@fail_block, mock_proc)

          expect(mock_proc).to receive(:call).with(mock_context)

          capture(:stdout) do
            instance._fail(mock_context)
          end
        end
      end

      context 'context does not match conditions' do
        before(:each) do
          allow(instance).to receive(:matches_context?).and_return(false)
        end

        it 'should not invoke the previously stored block' do
          mock_context = double(:context)

          mock_proc = double(:proc)
          instance.instance_variable_set(:@fail_block, mock_proc)

          expect(mock_proc).to_not receive(:call)

          instance._fail(mock_context)
        end
      end
    end
  end
end
