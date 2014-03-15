require File.expand_path('../pusher.rb', __FILE__)
require File.expand_path('../single_instance.rb', __FILE__)

if __FILE__ == $0
  single_instance do
    if ARGV[0] || ClientConfig['MANUAL_REFRESH']
      Pusher.named_update(ARGV[0])
    else
      puts "Usage: cli git@github.com:user/repo.git"
    end
  end
end
