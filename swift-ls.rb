#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20211021-055255'

if ARGV.include?("-h")
  puts <<-eos
  usage:
   #{File.basename(__FILE__)} (container)

  note:
   if no container is specified, top container list will be shown
  eos
  exit
end

command = if container=ARGV[0]
            "swift list #{container}"
          else
            "swift list"
          end
puts "# #{command}"
system command

