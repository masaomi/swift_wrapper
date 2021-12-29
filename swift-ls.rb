#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20211229-135723'

if ARGV.include?("-h")
  puts <<-eos
  usage:
   #{File.basename(__FILE__)} (container) (top_directory) (--full) (--lh) (--debug)

  option:
   --full: show full list (default: off, only show the top directory (of the ojbect in the container)
   --lh: show container, object size appropriately

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
lh = ARGV.index("--lh")
$debug = ARGV.index("--debug")
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
def stat(container, object=nil)
  if container and object
    command = "swift stat #{container} #{object.chomp} | grep 'Content Length'"
    puts "# #{command}" if $debug
    ret = `#{command}`
    size = ret.split(":").last.strip.to_i # byte
  elsif container
    command = "swift stat #{container} | grep Bytes"
    puts "# #{command}" if $debug
    ret = `#{command}`
    size = ret.split(":").last.strip.to_i # byte
  end
end
def readable_size(byte)
  size = if byte > 2**40
           "%.2fTB" % (byte.to_f/2**40)
         elsif byte > 2**20
           "%.2fGB" % (byte.to_f/2**30)
         elsif byte > 2**20
           "%.2fMB" % (byte.to_f/2**20)
         elsif byte > 2**10
           "%.2fkB" % (byte.to_f/2**10)
         else
           "#{byte}B"
         end
end

unless custom_process
  puts "# #{command}"
  if lh
    if container and (top_directory or full)
      total_size = 0
      object_size = {}
      IO.popen(command).each do |object|
        size = stat(container.chomp, object.chomp)
        object_size[object.chomp] = size
        total_size += size
      end
      object_size.each do |object, byte|
        puts "#{object}: #{readable_size(byte)}"
      end
      puts "total: #{readable_size(total_size)}"
    elsif full
      IO.popen(command).each do |container|
        unless container =~ /_segments/
          container_size = 0
          subcommand = "swift list #{container.chomp}"
          puts command if $debug
          IO.popen(subcommand).each do |object|
            size = stat(container.chomp, object.chomp)
            container_size += size
          end
          puts "#{container.chomp}: #{readable_size(container_size)}"
        end
      end
    else # only container list
      total = 0
      IO.popen(command).each do |container|
        unless container =~ /_segments/
          container_size = stat(container.chomp)
          total += container_size
          puts "#{container.chomp}: #{readable_size(container_size)}"
        end
      end
      puts "# total: #{readable_size(total)}"
    end
  else
    system command
  end
else
  case custom_process
  when "container"
    puts "# #{command} + only top directories"
    top_directories = {}
    top_directory_size = {}
    IO.popen(command).each do |object|
      top_directory =  object.split('/').first
      top_directories[top_directory] = true
      if lh
        size = stat(container, object)
        top_directory_size[top_directory] ||= 0
        top_directory_size[top_directory] += size
      end
    end
    if lh
      total_size = 0
      top_directories.keys.each do |top_directory|
        size = top_directory_size[top_directory]
        total_size += size
        size = readable_size(size)
        puts "#{top_directory.chomp}: #{size}"
      end
      puts "total: #{readable_size(total_size)}"
    else
      puts top_directories.keys.join
    end
  when "full"
    IO.popen(command).each do |container|
      unless container =~ /_segments/
        container_size = 0
        object_size = {}
        subcommand = "swift list #{container.chomp}"
        if lh
          IO.popen(subcommand).each do |object|
            size = stat(container.chomp, object.chomp)
            object_size[object.chomp] = size
            container_size += size
          end
          puts "#{container.chomp}: #{readable_size(container_size)}"
          object_size.each do |object, byte|
            puts "\t#{object}: #{readable_size(byte)}"
          end
        else
          puts "#{container.chomp}:"
          system subcommand
        end
        puts
      end
    end
  end
end


