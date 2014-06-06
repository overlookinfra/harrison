module Harrison
  class Package
    attr_reader :ssh
    attr_accessor :options

    def initialize(opts={})
      @options = opts

      self.class.option_helper(:build_host)
      self.class.option_helper(:build_user)
      self.class.option_helper(:commit)
      self.class.option_helper(:purge)
    end

    def ssh
      @ssh ||= Harrison::SSH.new(host: build_host, user: build_user)
    end

    private

    def self.option_helper(option)
      define_method option do
        @options[option]
      end

      define_method "#{option}=" do |val|
        @options[option] = val
      end
    end
  end
end
