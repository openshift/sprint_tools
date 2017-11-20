require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'yaml'

module SprintTools
  class TestCase < MiniTest::Spec
    ASSETS_DIR = File.expand_path File.join(File.dirname(__FILE__), 'files')
    STD_CONFIG_FILE = File.join(ASSETS_DIR, 'std_config.yml')

    def load_std_config
      hashes = {}
      hashes['trello'] = YAML.load_file(STD_CONFIG_FILE)
      OpenStruct.new(hashes)
    end

    def load_conf(klass, args, single = false)
      if single
        klass.new(args)
      else
        Hash[*args.map do |key, val|
               [key, klass.new(val)]
             end.flatten]
      end
    end
  end
end
