module Harrison
  class Deploy::Phase
    attr_accessor :name

    def initialize(name, &phase_config)
      self.name = name

      @conditions = Array.new

      yield self if block_given?
    end

    def add_condition(&block)
      @conditions << block
    end

    # Ensure all conditions eval to true for this context.
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
      return unless matches_context?(context)

      if @run_block
        puts "[#{context.host}] Executing \"#{self.name}\"..."
        @run_block.call(context)
      end
    end

    def _fail(context)
      # Ensure all conditions eval to true for this context.
      return unless matches_context?(context)

      if @fail_block
        puts "[#{context.host}] Reverting \"#{self.name}\"..."
        @fail_block.call(context)
      end

    end
  end
end
