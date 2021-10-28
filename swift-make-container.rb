#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20211021-055117'

unless new_container=ARGV[0]
  puts <<-eos
  usage:
   #{File.basename(__FILE__)} [container name]
  eos
  exit
end

command = "swift post #{new_container}"
puts "# #{command}"
system command
