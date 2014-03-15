def single_instance(&block)
  if File.open($0).flock(File::LOCK_EX|File::LOCK_NB)
    block.call
  else
    warn "#{$0}: another instance is already running"
  end
end
