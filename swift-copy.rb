#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20211028-085207'
# ref: https://www.dkrz.de/up/systems/swift/swift

help =->() do
  puts <<-eos
  usage:
   upload:   #{File.basename(__FILE__)} [target file] [target container] (--keep-split)
   download: #{File.basename(__FILE__)} [target container] ([target object (full path)])
  e.g.
   * swift upload: #{File.basename(__FILE__)} text.txt masa-backup
   * swift download: #{File.basename(__FILE__)} masa-backup text.txt 
  ref.
   * swift list (~/bin/swift-ls): show container list
   * swift post (~/bin/swift-make-container): make a container
  note:
   * you need to make a container in advance of uploading
   * if you do not set target object in downloading, all objects in the container will be downloaded
  options:
   --keep-split: not delete split files in local (default: delete after md5sum check)
  eos
  exit
end

unless target1=ARGV[0]
  help.()
end
target2=ARGV[1]
keep_split = ARGV.index("--keep-split")

container_list = IO.popen("swift list") do |io|
  list = {}
  while line=io.gets
    list[line.chomp] = true
  end
  list
end

# p container_list

if File.exist?(target1) and target2 and container_list[target2] 
  # upload
  mode = :upload
  object = target1
  container = target2
  option = "--segment-size 5000000000 "
elsif container_list[target1]
  mode = :download
  container = target1
  object = target2
elsif !container_list[target1] and !container_list[target2]
  warn "# WARN: neither #{target1} nor #{target2} is found as a container"
  warn "# please check by swift list"
  warn "# or please make a container by swift post"
  help.()
else
  help.()
end

command = case mode
          when :upload
            "swift upload #{option}#{container} #{object}"
          when :download
            if target2
              "swift download #{container} #{object}"
            else
              "swift download #{container}"
            end
          end

#warn "continue? [Y/n]"
#yesno = IO::gets.chomp
#exit if yesno == "n"

warn "# #{command}"
ret = `#{command}`
warn ret

# md5sum and size check only for upload
if mode == :upload
  # object list
  object_list = IO.popen("swift list #{container}") do |io|
    list = []
    while line=io.gets
      unless line =~ /not found/
        list << line.chomp
      end
    end
    list
  end
  # local file list
  local_file_list = []
  require 'find'
  Find.find(object) do |item|
    unless File.directory?(item)
      local_file_list << item
    end
  end
  #p object_list
  #p local_file_list

  # ETag (md5sum) + Content Length (file size) check
  object_etag_list = {} 
  object_size_list = {}
  segmented_object_list = []
  local_file_list.each do |file|
    unless object_list.include?(file)
      raise "WARNING: local file, #{file}, does not exist in container, #{container}"
    end
    object = file
    command = "swift stat #{container} #{object}| grep ETag"
    warn "# #{command}"
    etag_ = `#{command}`
    if etag_ =~ /\"/
      segmented_object_list << object
    end
    etag = etag_.split(":").last.strip.gsub('"', '').chomp
    object_etag_list[object] = etag

    command = "swift stat #{container} #{object}| grep 'Content Length'"
    warn "# #{command}"
    content_length = `#{command}`.split(":").last.strip.gsub('"', '').chomp
    object_size_list[object] = content_length
  end

  # local file md5sum and size check
  local_file_size_list = {}
  local_file_md5sum_list = {}
  local_file_list.each do |file|
    command = "ls -l #{file}"
    #-rw-rw-r--+ 1 masaomi SG_Employees 32435220453 Nov 23 14:25 archives_2019.tgz
    warn "# #{command}"
    file_size = `#{command}`.split[4].strip
    local_file_size_list[file] = file_size

    unless segmented_object_list.include?(file)
      command = "md5sum #{file}"
      warn "# #{command}"
      md5sum = `#{command}`.split.first
      local_file_md5sum_list[file] = md5sum
    end
  end
  #p object_etag_list
  #p local_file_md5sum_list
  #puts
  #p object_size_list
  #p local_file_size_list

  local_file_split_md5sum_list = {}
  require 'fileutils'
  FileUtils.mkdir_p "split"
  segmented_object_list.each do |file|
    command = "split -b 5000000000 -d #{file} split/#{File.basename(file)}_"
    warn "# #{command}"
    system command
    Dir["split/#{File.basename(file)}_*"].sort.each do |split_file|
      command = "md5sum #{split_file}"
      warn "# #{command}"
      md5sum = `#{command}`.split.first
      local_file_split_md5sum_list[file] ||= []
      local_file_split_md5sum_list[file] << md5sum
    end
  end
  require 'digest/md5'
  #p local_file_split_md5sum_list
  local_file_split_md5sum_list.each do |object, md5sum_list|
    #puts [object, Digest::MD5.hexdigest(md5sum_list.join)].join("\t")
    md5sum = Digest::MD5.hexdigest(md5sum_list.join)
    local_file_md5sum_list[object] = md5sum
  end
  #p local_file_md5sum_list

  # check local files and container objects
  pass_md5sum = true 
  local_file_list.each do |file|
    object = file
    unless object_etag_list[object] == local_file_md5sum_list[file]
      warn "# WARNING: ETag and md5sum are different for #{file}"
      warn "# container: #{container}, object: #{object}, ETag: #{object_etag_list[object]}"
      warn "# localfile: #{file}, md5sum: #{local_file_md5sum_list[file]}"
      pass_md5sum = false
    else
      puts "# PASS: md5sum (Etag) check for #{file}: #{object_etag_list[object]}"
    end
  end
  pass_size = true
  local_file_list.each do |file|
    object = file
    unless object_size_list[object] == local_file_size_list[file]
      warn "# WARNING: File sizes are different for #{file}"
      warn "# container: #{container}, object: #{object}, size: #{object_size_list[object]}"
      warn "# localfile: #{file}, size: #{local_file_size_list[file]}"
      pass_size = false
    else
      puts "# PASS: file size check for #{file}: #{object_size_list[object]}"
    end
  end

  # delete split files
  if !keep_split and pass_md5sum and pass_size
    FileUtils.rm_r "split"
  end
end

