require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'yaml'

module SprintTools
  class TestCase < MiniTest::Spec
    ASSETS_DIR = File.expand_path File.join(File.dirname(__FILE__), 'files')
    STD_CONFIG_FILE = File.join(ASSETS_DIR, 'std_config.yml')
    NO_DEP_WORK_BDS_CONFIG_FILE = File.join(ASSETS_DIR, 'no_dependent_work_boards_config.yml')

    def load_config(config_file)
      hashes = {}
      hashes['trello'] = YAML.load_file(config_file)
      OpenStruct.new(hashes)
    end

    def load_std_config
      load_config(STD_CONFIG_FILE)
    end

    def load_no_dep_work_boards_config
      load_config(NO_DEP_WORK_BDS_CONFIG_FILE)
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
