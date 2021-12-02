require 'json'
require 'yaml'
require 'etc'
require 'fileutils'
require 'pathname'
require 'open3'

# 
# 
# 
# OS 
# 
# 
# 

    # this statment was extracted from the ptools gem, credit should go to them
    # https://github.com/djberg96/ptools/blob/master/lib/ptools.rb
    # The WIN32EXTS string is used as part of a Dir[] call in certain methods.
    if File::ALT_SEPARATOR
        MSWINDOWS = true
        if ENV['PATHEXT']
            WIN32EXTS = ('.{' + ENV['PATHEXT'].tr(';', ',').tr('.','') + '}').downcase
        else
            WIN32EXTS = '.{exe,com,bat}'
        end
    else
        MSWINDOWS = false
    end

    # TODO: look into using https://github.com/piotrmurach/tty-platform

    # 
    # Groups
    # 
    module OS
        
        # create a singleton class
        CACHE = Class.new do
            attr_accessor :is_windows, :is_mac, :is_linux, :is_unix, :is_debian, :is_ubuntu, :version
        end.new
        
        def self.is?(adjective)
            # summary:
                # this is a function created for convenience, so it doesn't have to be perfect
                # you can use it to ask about random qualities of the current OS and get a boolean response
            # convert to string (if its a symbol)
            adjective = adjective.to_s.downcase
            case adjective
                when 'windows'
                    if CACHE::is_windows == nil
                        CACHE::is_windows = (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
                    end
                    return CACHE::is_windows
                when 'mac'
                    if CACHE::is_mac == nil
                        CACHE::is_mac = (/darwin/ =~ RUBY_PLATFORM) != nil
                    end
                    return CACHE::is_mac
                when 'linux'
                    if CACHE::is_linux == nil
                        CACHE::is_linux = (not OS.is?(:windows)) && (not OS.is?(:mac))
                    end
                    return CACHE::is_linux
                when 'unix'
                    if CACHE::is_unix == nil
                        CACHE::is_unix = not(OS.is?(:windows))
                    end
                    return CACHE::is_unix
                when 'debian'
                    if CACHE::is_debian == nil
                        CACHE::is_debian = File.file?('/etc/debian_version')
                    end
                    return CACHE::is_debian
                when 'ubuntu'
                    if CACHE::is_ubuntu == nil
                        CACHE::is_ubuntu = OS.has_command('lsb_release') && `lsb_release -a`.match(/Distributor ID:[\s\t]*Ubuntu/)
                    end
                    return CACHE::is_ubuntu
            end
        end
        
        def self.path_for_executable(name_of_executable)
            program = name_of_executable
            # this method was extracted from the ptools gem, credit should go to them
            # https://github.com/djberg96/ptools/blob/master/lib/ptools.rb
            # this complex method is in favor of just calling the command line because command line calls are slow
            path=ENV['PATH']
            if path.nil? || path.empty?
                raise ArgumentError, "path cannot be empty"
            end

            # Bail out early if an absolute path is provided.
            if program =~ /^\/|^[a-z]:[\\\/]/i
                program += WIN32EXTS if MSWINDOWS && File.extname(program).empty?
                found = Dir[program].first
                if found && File.executable?(found) && !File.directory?(found)
                    return found
                else
                    return nil
                end
            end

            # Iterate over each path glob the dir + program.
            path.split(File::PATH_SEPARATOR).each{ |dir|
                dir = File.expand_path(dir)

                next unless File.exist?(dir) # In case of bogus second argument
                file = File.join(dir, program)

                # Dir[] doesn't handle backslashes properly, so convert them. Also, if
                # the program name doesn't have an extension, try them all.
                if MSWINDOWS
                    file = file.tr("\\", "/")
                    file += WIN32EXTS if File.extname(program).empty?
                end

                found = Dir[file].first

                # Convert all forward slashes to backslashes if supported
                if found && File.executable?(found) && !File.directory?(found)
                    found.tr!(File::SEPARATOR, File::ALT_SEPARATOR) if File::ALT_SEPARATOR
                    return found
                end
            }

            return nil
        end
        
        def self.has_command(name_of_executable)
            return OS.path_for_executable(name_of_executable) != nil
        end
    end




# 
# 
# 
# Files
# 
# 
# 

    

    if OS.is?("unix")
        HOME = Etc.getpwuid.dir
    else # windows
        HOME = "C:"+`echo %HOMEPATH%`.chomp
    end

    class String
        # this is for easy creation of cross-platform filepaths
        # ex: "foldername"/"filename"
        def /(next_string)
            if OS.is?("windows")
                next_string_without_leading_or_trailing_slashes = next_string.gsub(/(^\\|^\/|\\$|\/$)/,"")
                output = self + "\\" + next_string
                # replace all forward slashes with backslashes
                output.gsub(/\//,"\\")
            else
                File.join(self, next_string)
            end
        end
    end

    module FileSystem
        # This is a combination of the FileUtils, File, Pathname, IO, Etc, and Dir classes,
        # along with some other helpful methods
        # It is by-default forceful (dangerous/overwriting)
        # it is made to get things done in a no-nonsense error-free way and to have every pratical tool in one place

        # FUTURE add
            # change_owner
            # set_permissions
            # relative_path_between
            # relative_path_to
            # add a force: true option to most of the commands
            # zip
            # unzip
        
        def self.write(data, to:nil)
            # make sure the containing folder exists
            FileSystem.makedirs(File.dirname(to))
            # actually download the file
            IO.write(to, data)
        end
        
        def self.append(data, to:nil)
            FileSystem.makedirs(File.dirname(to))
            return open(to, 'a') do |file|
                file << data
            end
        end

        def self.save(value, to:nil, as:nil)
            # assume string if as was not given
            if as == nil
                as = :s
            end
            
            # add a special exception for csv files
            case as
            when :csv
                require 'csv'
                FS.write(value.map(&:to_csv).join, to: to)
            else
                require 'json'
                require 'yaml'
                conversion_method_name = "to_#{as}"
                if value.respond_to? conversion_method_name
                    # this is like calling `value.to_json`, `value.to_yaml`, or `value.to_csv` but programatically
                    string_value = value.public_send(conversion_method_name)
                    if not string_value.is_a?(String)
                        raise <<~HEREDOC
                        
                        
                            The FileSystem.save(value, to: #{to.inspect}, as: #{as.inspect}) had a problem.
                            The as: #{as}, gets converted into value.to_#{as}
                            Normally that returns a string that can be saved to a file
                            However, the value.to_#{as} did not return a string.
                            Value is of the #{value.class} class. Add a `to_#{as}` 
                            method to that class that returns a string to get FileSystem.save() working
                        HEREDOC
                    end
                    FS.write(string_value, to:to)
                else
                    raise <<~HEREDOC
                    
                    
                        The FileSystem.save(value, to: #{to.inspect}, as: #{as.inspect}) had a problem.
                        
                        The as: #{as}, gets converted into value.to_#{as}
                        Normally that returns a string that can be saved to a file
                        However, the value.to_#{as} is not a method for value
                        Value is of the #{value.class} class. Add a `to_#{as}` 
                        method to that class that returns a string to get FileSystem.save() working
                    HEREDOC
                end
            end
        end
        
        def self.read(filepath)
            begin
                return IO.read(filepath)
            rescue Errno::ENOENT => exception
                return nil
            end
        end
        
        def self.delete(path)
            if File.file?(path)
                File.delete(path)
            elsif File.directory?(path)
                FileUtils.rm_rf(path)
            end
        end
        
        def self.username
            if OS.is?(:windows)
                return File.basename(ENV["userprofile"])
            else
                return Etc.getlogin
            end
        end
        
        def self.makedirs(path)
            FileUtils.makedirs(path)
        end
        
        def self.in_dir(path_to_somewhere)
            # save the current working dir
            current_dir = Dir.pwd
            # switch dirs
            Dir.chdir(path_to_somewhere)
            # do the thing
            output = yield
            # switch back
            Dir.chdir(current_dir)
            return output
        end
        
        def self.merge(from, into: nil, force: true)
            to = into
            if !FS.exist?(from)
                raise <<~HEREDOC
                    
                    
                    When calling FileSystem.merge(#{from.inspect}, into: #{into.inspect})
                    The path: #{from.inspect}
                    Doesn't exist
                HEREDOC
            end
            
            # recursive case (folder)
            if FS.is_folder(from)
                # if theres a target file in the way
                if FS.exist?(to) && ( !FS.is_folder(to) )
                    if force
                        # remove it
                        FS.delete(to)
                    else
                        # continue with the process
                        return
                    end
                end
                # create a folder if needed
                if !FS.exist?(to)
                    FS.touch_dir(to)
                end
                # become recursive for all contents
                for each in FS.ls(from)
                    FS.merge(from/each, into: to/each, force: force)
                end
            # base case (file)
            else
                if FS.exist?(to)
                    if force
                        FS.delete(to)
                    else
                        # do nothing
                        return
                    end
                end
                FS.copy(FS.basename(from), from: FS.dirname(from), to: FS.dirname(to))
            end
        end
        
        def self.copy(item, from:nil, to:nil, new_name:nil, force: true, preserve: false, dereference_root: false)
            from = from/item
            if new_name == ""
                raise "\n\nFileSystem.copy() needs a new_name: argument\nset new_name:nil if you wish the file/folder to keep the same name\ne.g. FileSystem.copy(thing, from:'place', to:'place', new_name:nil)"
            elsif new_name == nil
                new_name = File.basename(from)
            end
            # make sure the "to" path exists
            FileSystem.touch_dir(to)
            # perform the copy
            FileUtils.copy_entry(from, to/new_name, preserve, dereference_root, force)
        end

        def self.move(item, from:nil, to:nil, new_name:"", force: true, noop: nil, verbose: nil, secure: nil)
            from = from/item
            if new_name == ""
                raise "\n\nFileSystem.move() needs a new_name: argument\nset new_name:nil if you wish the file/folder to keep the same name\ne.g. FileSystem.move(thing, from:'place', to:'place', new_name:nil)"
            elsif new_name == nil
                new_name = File.basename(from)
            end
            # make sure the "to" path exists
            FileSystem.touch_dir(to)
            # perform the move
            FileUtils.move(from, to/new_name, force: force, noop: noop, verbose: verbose, secure: secure)
        end
        
        def self.rename(path, new_name:nil, force: true)
            if File.dirname(new_name) != "."
                raise <<~HEREDOC
                    
                    
                    When using FileSystem.rename(path, new_name)
                        The new_name needs to be a filename, not a file path
                        e.g. "foo.txt" not "a_folder/foo.txt"
                        
                        If you want to move the file, use FileSystem.move(from:nil, to:nil, new_name:"")
                HEREDOC
            end
            to = FileSystem.dirname(path)/new_name
            # if they are different
            if FS.absolute_path(to) != FS.absolute_path(path)
                # make sure the path is clear
                if force
                    FileSystem.delete(to)
                end
                # perform the rename
                return File.rename(path, to)
            end
        end
        
        def self.touch(path)
            FileSystem.makedirs(File.dirname(path))
            if not FileSystem.file?(path)
                return IO.write(path, "")
            end
        end
        singleton_class.send(:alias_method, :touch_file, :touch)
        singleton_class.send(:alias_method, :ensure_file_exists, :touch)
        
        def self.ensure_folder_exists(path)
            if not FileSystem.directory?(path)
                FileUtils.makedirs(path)
            end
        end
        singleton_class.send(:alias_method, :touch_dir, :ensure_folder_exists)
        singleton_class.send(:alias_method, :touch_folder, :ensure_folder_exists)
        
        # Pathname aliases
        def self.absolute_path?(path)
            Pathname.new(path).absolute?
        end
        singleton_class.send(:alias_method, :is_absolute_path, :absolute_path?)
        singleton_class.send(:alias_method, :abs?, :absolute_path?)
        singleton_class.send(:alias_method, :is_abs, :abs?)
        
        def self.relative_path?(path)
            Pathname.new(path).relative?
        end
        singleton_class.send(:alias_method, :is_relative_path, :relative_path?)
        singleton_class.send(:alias_method, :rel?, :relative_path?)
        singleton_class.send(:alias_method, :is_rel, :rel?)
        
        def self.path_pieces(path)
            # use this function like this:
            # *path, filename, extension = FS.path_pieces('/Users/jeffhykin/Desktop/place1/file1.pdf')
            pieces = Pathname(path).each_filename.to_a
            extname = File.extname(pieces[-1])
            basebasename = pieces[-1][0...(pieces[-1].size - extname.size)]
            # add the root if the path is absolute
            if FileSystem.abs?(path)
                if not OS.is?("windows")
                    pieces.unshift('/')
                else
                    # FUTURE: eventually make this work for any drive, not just the current drive
                    pieces.unshift('\\')
                end
            end
            return [ *pieces[0...-1], basebasename, extname ]
        end
        
        # dir aliases
        def self.home
            HOME
        end
        def self.glob(path)
            Dir.glob(path, File::FNM_DOTMATCH) - %w[. ..]
        end
        def self.list_files(path=".")
            Dir.children(path).map{|each| path/each }.select {|each| FileSystem.file?(each)}
        end
        def self.list_folders(path=".")
            Dir.children(path).map{|each| path/each }.select {|each| FileSystem.directory?(each)}
        end
        def self.ls(path=".")
            Dir.children(path)
        end
        def self.pwd
            FS.join(Dir.pwd, "")
        end
        def self.cd(*args, verbose: false)
            if args.size == 0
                args[0] = FS.home
            end
            FileUtils.cd(args[0], verbose: verbose)
        end
        def self.chdir(*args)
            FS.cd(*args)
        end
        
        # File aliases
        def self.time_access(*args)
            File.atime(*args)
        end
        def self.time_created(*args)
            File.birthtime(*args)
        end
        def self.time_modified(*args)
        end
        
        def self.join(*args)
            if OS.is?("windows")
                folders_without_leading_or_trailing_slashes = args.map do |each|
                    # replace all forward slashes with backslashes
                    backslashed_only = each.gsub(/\//,"\\")
                    # remove leading/trailing backslashes
                    backslashed_only.gsub(/(^\\|^\/|\\$|\/$)/,"")
                end
                # join all of them with backslashes
                folders_without_leading_or_trailing_slashes.join("\\")
            else
                File.join(*args)
            end
        end
        
        # inherit from File
        def self.absolute_path(*args)
            File.absolute_path(*args)
        end
        def self.dirname(*args)
            File.dirname(*args)
        end
        def self.basename(*args)
            File.basename(*args)
        end
        def self.extname(*args)
            File.extname(*args)
        end
        def self.folder?(*args)
            File.directory?(*args)
        end
        singleton_class.send(:alias_method, :is_folder, :folder?)
        singleton_class.send(:alias_method, :dir?, :folder?)
        singleton_class.send(:alias_method, :is_dir, :dir?)
        singleton_class.send(:alias_method, :directory?, :folder?)
        singleton_class.send(:alias_method, :is_directory, :directory?)
        
        def self.exists?(*args)
            File.exist?(*args)
        end
        singleton_class.send(:alias_method, :does_exist, :exists?)
        singleton_class.send(:alias_method, :exist?, :exists?)
        
        def self.file?(*args)
            File.file?(*args)
        end
        singleton_class.send(:alias_method, :is_file, :file?)
        
        def self.empty?(*args)
            File.empty?(*args)
        end
        singleton_class.send(:alias_method, :is_empty, :empty?)
        
        def self.executable?(*args)
            File.executable?(*args)
        end
        singleton_class.send(:alias_method, :is_executable, :executable?)
        
        def self.symlink?(*args)
            File.symlink?(*args)
        end
        singleton_class.send(:alias_method, :is_symlink, :symlink?)
        
        def self.owned?(*args)
            File.owned?(*args)
        end
        singleton_class.send(:alias_method, :is_owned, :owned?) 
        
        def self.pipe?(*args)
            File.pipe?(*args)
        end
        singleton_class.send(:alias_method, :is_pipe, :pipe?) 
        
        def self.readable?(*args)
            File.readable?(*args)
        end
        singleton_class.send(:alias_method, :is_readable, :readable?) 
        
        def self.size?(*args)
            if File.directory?(args[0])
                # recursively get the size of the folder
                return Dir.glob(File.join(args[0], '**', '*')).map{ |f| File.size(f) }.inject(:+)
            else
                File.size?(*args)
            end
        end
        singleton_class.send(:alias_method, :size_of, :size?) 
        
        def self.socket?(*args)
            File.socket?(*args)
        end
        singleton_class.send(:alias_method, :is_socket, :socket?) 
        
        def self.world_readable?(*args)
            File.world_readable?(*args)
        end
        singleton_class.send(:alias_method, :is_world_readable, :world_readable?) 
        
        def self.world_writable?(*args)
            File.world_writable?(*args)
        end
        singleton_class.send(:alias_method, :is_world_writable, :world_writable?) 
        
        def self.writable?(*args)
            File.writable?(*args)
        end
        singleton_class.send(:alias_method, :is_writable, :writable?) 
        
        def self.writable_real?(*args)
            File.writable_real?(*args)
        end
        singleton_class.send(:alias_method, :is_writable_real, :writable_real?) 
        
        def self.expand_path(*args)
            File.expand_path(*args)
        end
        def self.mkfifo(*args)
            File.mkfifo(*args)
        end
        def self.stat(*args)
            File.stat(*args)
        end
        
        def self.download(the_url, to:nil)
            require 'open-uri'
            FileSystem.write(open(URI.encode(the_url)).read, to: to)
        end
        
        def self.online?
            require 'open-uri'
            begin
                true if open("http://www.google.com/")
            rescue
                false
            end
        end
        
        class ProfileHelper
            def initialize(unqiue_id)
                function_def = "ProfileHelper.new(unqiue_id)"
                if unqiue_id =~ /\n/
                    raise <<~HEREDOC
                        
                        
                        Inside the #{function_def.color_as :code}
                        the unqiue_id contains a newline (\\n)
                        
                        unqiue_id: #{"#{unqiue_id}".inspect}
                        
                        Sadly newlines are not allowed in the unqiue_id due to how they are searched for.
                        Please provide a unqiue_id that doesn't have newlines.
                    HEREDOC
                end
                if "#{unqiue_id}".size < 5 
                    raise <<~HEREDOC
                        
                        
                        Inside the #{function_def.color_as :code}
                        the unqiue_id is: #{"#{unqiue_id}".inspect}
                        
                        That's not even 5 characters. Come on man, there's going to be problems if the unqiue_id isn't unqiue
                        generate a random number (once), then put the name of the service at the front of that random number
                    HEREDOC
                end
                @unqiue_id = unqiue_id
            end
            
            def bash_comment_out
                ->(code) do
                    "### #{code}"
                end
            end
            
            def add_to_bash_profile(code)
                uniquely_append(code, HOME/".bash_profile", bash_comment_out)
            end
            
            def add_to_zsh_profile(code)
                uniquely_append(code, HOME/".zprofile", bash_comment_out)
            end
            
            def add_to_bash_rc(code)
                uniquely_append(code, HOME/".bashrc", bash_comment_out)
            end
            
            def add_to_zsh_rc(code)
                uniquely_append(code, HOME/".zshrc", bash_comment_out)
            end
            
            def uniquely_append(string_to_add, location_of_file, comment_out_line)
                _UNQIUE_HELPER = 'fj03498hglkasjdgoghu2904' # dont change this, its a 1-time randomly generated string
                final_string = "\n"
                final_string += comment_out_line["start of ID: #{@unqiue_id} #{_UNQIUE_HELPER}"] + "\n"
                final_string += comment_out_line["NOTE! if you remove this, remove the whole thing (don't leave a dangling start/end comment)"] + "\n"
                final_string += string_to_add + "\n"
                final_string += comment_out_line["end of ID: #{@unqiue_id} #{_UNQIUE_HELPER}"]
                
                # open the existing file if there is one
                file = FS.read(location_of_file) || ""
                # remove any previous versions
                file.gsub!(/### start of ID: (.+) #{_UNQIUE_HELPER}[\s\S]*### end of ID: \1 #{_UNQIUE_HELPER}/) do |match|
                    if $1 == @unqiue_id
                        ""
                    else
                        match
                    end
                end
                # append the the new code at the bottom (highest priority)
                file += final_string
                # overwrite the file
                FS.write(file, to: location_of_file)
            end
        end
    end
    # create an FS singleton_class.send(:alias_method, :FS = :FileSystem)
    FS = FileSystem


# 
# 
# 
# Console
# 
# 
#
    class CommandResult
        def initialize(process: nil, stdout_text:nil, stderr_text:nil, combined_text: nil)
            @stdout_text = stdout_text
            @stdout_text = stdout_text
            @combined_text = combined_text
            @process = process
        end
        
        # TODO: enable this when interactive commands are added
        # def write(text)
        # end
        
        def text(from:nil)
            case from
            when :stdout
                return @stdout_text
            when :stderr
                return @stderr_text
            else
                return @combined_text
            end
        end
        
        def exitcode
            return @process && @process.exitstatus
        end
        
        def success?
            return @process && @process.success?
        end
        
        class Error < Exception
            attr_accessor :command_result, :message
            
            def initialize(message, command_result)
                @message = message
                @command_result = command_result
            end
            
            def to_s
                return @message
            end
        end
    end

    Console = Class.new do
        
        CACHE = Class.new do
            attr_accessor :prompt
        end.new
        
        attr_accessor :verbose
        
        def _save_args
            if @args == nil
                @args = []
                for each in ARGV
                    @args << each
                end
            end
        end
        
        def args
            self._save_args()
            return @args
        end
        
        def stdin
            # save arguments before clearing them
            self._save_args()
            # must clear arguments in order to get stdin
            ARGV.clear
            # check if there is a stdin
            if !(STDIN.tty?)
                @stdin = $stdin.read
            end
            return @stdin
        end
        
        #
        # returns the command object, ignores errors
        #
        def run!(command, **keyword_arguments)
            require 'io/wait'
            if ! command.is_a?(Array) && ! command.is_a?(String)
                raise <<~HEREDOC
                    
                    
                    The argument for run!() must be a string or an Array
                HEREDOC
            end
            
            # FIXME: there is a problem with ruby open3: what if the executable name has a space in it and no arguments arg given
            if command.is_a?(String)
                command = [command]
            end
            stdin_text = keyword_arguments["stdin"] || ""
            stderr_text = ""
            stdout_text = ""
            combined_text = ""
            thread_reference = nil
            process = nil
            Open3.popen3(*command) {|stdin, stdout, stderr, thread|
                thread_reference = thread
                stdin.write(stdin_text)
                stdin.close
                loop do
                    if stdout.ready?
                        stdout_iter = stdout.read
                        stdout_text += stdout_iter
                        combined_text += stdout_iter
                    end
                    
                    if stderr.ready?
                        stderr_iter = stderr.read
                        stderr_text += stderr_iter
                        combined_text += stderr_iter
                    end
                    
                    if thread.status == false
                        process = thread.value
                        break
                    end
                end
            }
            # wait for command to end
            loop do
                if thread_reference && ( ! thread_reference.status)
                    break
                end
            end
            return CommandResult.new(process: process, stdout_text:stdout_text, stderr_text:stderr_text, combined_text: combined_text)
        end

        # 
        # returns true if successful, false/nil on error
        # 
        def run?(command, **keyword_arguments)
            result = Console.run!(command, **keyword_arguments)
            return result.success?
        end

        # 
        # returns process info if successful, raises error if command failed
        # 
        def run(command, **keyword_arguments)
            result = Console.run!(command, **keyword_arguments)
            # if ended with error
            if !result.success?
                # then raise an error
                raise CommandResult::Error.new <<~HEREDOC
                    
                    From Console.run(command)
                        The command: #{command}
                        Failed with a exitcode of: #{result.exitcode}
                        
                        #{"Hopefully there is additional error info above" if result.exitcode != 127}
                        #{"This likely means the command could not be found" if result.exitcode == 127}
                HEREDOC
            end
            return result
        end
        
        def path_for(name_of_executable)
            return OS.path_for_executable(name_of_executable)
        end
        
        def has_command(name_of_executable)
            return OS.has_command(name_of_executable)
        end
        alias :has_command? :has_command
        
        def as_shell_argument(argument)
            argument = argument.to_s
            if OS.is?(:unix)
                # use single quotes to perfectly escape any string
                return " '"+argument.gsub(/'/, "'\"'\"'")+"'"
            else
                # *sigh* Windows
                # this problem is unsovleable
                # see: https://superuser.com/questions/182454/using-backslash-to-escape-characters-in-cmd-exe-runas-command-as-example
                #       "The fact is, there's nothing that will escape " within quotes for argument passing. 
                #        You can brood over this for a couple of years and arrive at no solution. 
                #        This is just some of the inherent limitations of cmd scripting.
                #        However, the good news is that you'll most likely never come across a situation whereby you need to do so.
                #        Sure, there's no way to get echo """ & echo 1 to work, but that's not such a big deal because it's simply
                #        a contrived problem which you'll likely never encounter.
                #        For example, consider runas. It works fine without needing to escape " within quotes
                #        because runas knew that there's no way to do so and made internal adjustments to work around it.
                #        runas invented its own parsing rules (runas /flag "anything even including quotes") and does not
                #        interpret cmd arguments the usual way.
                #        Official documentation for these special syntax is pretty sparse (or non-existent).
                #        Aside from /? and help, it's mostly trial-and-error."
                # 
                
                
                # according to Microsoft see: https://docs.microsoft.com/en-us/archive/blogs/twistylittlepassagesallalike/everyone-quotes-command-line-arguments-the-wrong-way
                # the best possible (but still broken) implementation is to quote things 
                # in accordance with their default C++ argument parser
                # so thats what this function does
                
                # users are going to have to manually escape things like ^, !, % etc depending on the context they're used in
                
                simple_char = "[a-zA-Z0-9_.,;`=\\-*?\\/\\[\\]]"
                
                # if its a simple argument just pass it on
                if argument =~ /\A(#{simple_char})*\z/
                    return " #{argument}"
                # if it is complicated, then quote it and escape quotes
                else
                    # find any backslashes that come before a double quote or the ending of the argument
                    # then double the number of slashes
                    escaped = argument.gsub(/(\/+)(?="|\z)/) do |each_match|
                        "\/" * ($1.size * 2)
                    end
                    
                    # then find all the double quotes and escape them
                    escaped.gsub!(/"/, '\\"')
                    
                    # all of the remaining escapes are up to Windows user's/devs

                    return " \"#{escaped}\""
                end
            end
        end
        
        def make_arguments_appendable(arguments)
            safe_arguments = arguments.map do |each|
                Console.as_shell_argument(each)
            end
            return safe_arguments.join('')
        end
        
        # returns the locations where commands are stored from highest to lowest priority
        def command_sources()
            if OS.is?('unix')
                return ENV['PATH'].split(':')
            else
                return ENV['PATH'].split(';')
            end
        end
        
        def require_superuser()
            if OS.is?('unix')
                system("sudo echo 'permissions acquired'")
            else
                # check if already admin
                # $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                # $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                # FUTURE: add a check here and raise an error if not admin
                puts "(in the future this will be an automatic check)"
                puts "(if you're unsure, then the answer is probably no)"
                if Console.yes?("Are you running this \"as an Administrator\"?\n(caution: incorrectly saying 'yes' can cause broken systems)")
                    puts "assuming permissions are acquired"
                else
                    puts <<~HEREDOC
                        
                        You'll need to 
                        - close the current program
                        - reopen it "as Administrator"
                        - redo whatever steps you did to get here
                        
                    HEREDOC
                    Console.keypress("Press enter to end the current process", keys: [:return])
                    exit
                end
            end
        end
        
    end.new

    def log(*args)
        if Console.verbose
            puts(*args)
        end
    end 
