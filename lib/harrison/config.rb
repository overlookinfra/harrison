module Harrison
  class Config
    def initialize(opts={})
      self.class.config_keys.each do |key|
        self.class.send(:attr_accessor, key)
      end
    end

    def self.config_keys
      [
        :project,
        :git_src,
      ]
    end
  end
end
