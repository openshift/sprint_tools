#!/usr/bin/env ruby

require 'yaml'
require 'ostruct'

CONFIG_DIR = File.expand_path(File.join(File.dirname(__FILE__),'..','config'))

config_files = Dir.glob("#{CONFIG_DIR}/*.yml")

hashes = {}

config_files.each do |file|
  name = File.basename(file,".yml")
  hashes[name] = YAML.load_file(file)
end

CONFIG = OpenStruct.new(hashes)
