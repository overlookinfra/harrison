module Harrison
  class Deploy::Phase
    attr_accessor :name

    def initialize(name, &phase_config)
      self.name = name

      @conditions = Array.new

      @limit = nil
      @_run_count = 0
      @_fail_count = 0

      yield self if block_given?
    end

    def add_condition(&block)
      @conditions << block
    end

    # Limit the number of times this phase is invoked per deployment.
    def set_limit(n)
      @limit = n
    end

    # Check if all conditions eval to true for this context.
    def matches_context?(context)
      @conditions.all? { |cblock| cblock.call(context) }
    end

    def on_run(&block)
      @run_block = block
    end

    def on_fail(&block)
      @fail_block = block
    end

    # These should only be invoked by the deploy action.
    def _run(context)
      # Ensure limit has not been met.
      return unless @limit.nil? || @_run_count < @limit

      # Ensure all conditions eval to true for this context.
      return unless matches_context?(context)

      if @run_block
        puts "[#{context.host}] Executing \"#{self.name}\"..."
        @run_block.call(context)
        @_run_count += 1
      end
    end

    def _fail(context)
      # Ensure limit has not been met.
      return unless @limit.nil? || @_fail_count < @limit

      # Ensure all conditions eval to true for this context.
      return unless matches_context?(context)

      if @fail_block
        puts "[#{context.host}] Reverting \"#{self.name}\"..."
        @fail_block.call(context)
        @_fail_count += 1
      end

    end
  end
end
