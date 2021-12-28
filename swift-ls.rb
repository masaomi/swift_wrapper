#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20211228-063116'

if ARGV.include?("-h")
  puts <<-eos
  usage:
   #{File.basename(__FILE__)} (container) (top_directory) (--full)

  option:
   --full: show full list (default: off, only show the top directory (of the ojbect in the container)

  note:
   if no container is specified, top container list will be shown

  e.g.:
   #{File.basename(__FILE__)}: show all containers
   #{File.basename(__FILE__)} NGS-backup: show top directories in NGS-backup container
   #{File.basename(__FILE__)} NGS-backup DDBJ_upload_20160119: show objects of DDBJ_upload_20160119 in NGS-backup container
   #{File.basename(__FILE__)} --full: show all objects
   #{File.basename(__FILE__)} NGS-backup --full: show all objects only in NGS-backup container
   #
  eos
  exit
end

full = ARGV.index("--full")
container = if ARGV[0] !~ /^--/
              ARGV[0]
            end
top_directory = if ARGV[1] !~ /^--/
                  ARGV[1]
                end
custom_process = nil
command = if container and top_directory
            "swift list #{container} | grep #{top_directory}"
          elsif container and full
            "swift list #{container}"
          elsif container
            custom_process = "container"
            "swift list #{container}" # + custom process
          elsif full
            custom_process = "full"
            "swift list" # + custom_process
          else
            "swift list"
          end

unless custom_process
  puts "# #{command}"
  system command
else
  case custom_process
  when "container"
    puts "# #{command} + only top directories"
    top_directories = {}
    IO.popen(command).each do |line|
      top_directory =  line.split('/').first
      top_directories[top_directory] = true
    end
    puts top_directories.keys.join("\n")
  when "full"
    IO.popen(command).each do |container|
      unless container =~ /_segments/
        puts "#{container.chomp}:"
        subcommand = "swift list #{container}"
        system subcommand
        puts
      end
    end
  end
end


