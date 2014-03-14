config_file = File.expand_path('../config.rb', __FILE__)
abort "Please create a config.rb file (see config.example.rb)." unless File.exist?(config_file)
require config_file

module ClientConfig
  extend self

  def [](key)
    ENV[key] || Object.const_get(key)
  end
end
