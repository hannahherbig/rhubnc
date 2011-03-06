#
# rhubnc: rhuidean-based IRC bouncer
# lib/rhubnc.rb: startup routines, etc
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(logger optparse yaml).each { |m| require m }

# Import required application modules
#%w().each { |m| require 'rhubnc/' + m }

# Check for rhuidean
begin
    require 'rhuidean'
rescue LoadError
    puts 'rhubnc: unable to load rhuidean'
    puts 'rhubnc: this library is required for IRC communication'
    puts 'rhubnc: gem install --remote rhuidean'
    abort
else
    require 'rhuidean/stateful_client'
end

# The main application class
class Bouncer

    ##
    # mixins
    include Loggable      # Magic logging from rhuidean

    ##
    # constants

    # Project name
    ME = 'rhubnc'

    # Version number
    V_MAJOR  = 0
    V_MINOR  = 0
    V_PATCH  = 1

    VERSION  = "#{V_MAJOR}.#{V_MINOR}.#{V_PATCH}"

    # Configuration data
    @@config = nil

    # Debug mode?
    @@debug = false

    ##
    # Create a new +Bouncer+ object, which starts and runs the entire
    # application. Everything starts and ends here.
    #
    # return:: self
    #
    def initialize

        # Our logger
        @logger = nil

        rhu = Rhuidean::VERSION

        puts "#{ME}: version #{VERSION} (rhuidean-#{rhu}) [#{RUBY_PLATFORM}]"

        # Check to see if we're running on a decent version of ruby
        if RUBY_VERSION < '1.8.6'
            puts "#{ME}: requires at least ruby 1.8.6"
            puts "#{ME}: you have #{RUBY_VERSION}"
            abort
        elsif RUBY_VERSION < '1.9.1'
            puts "#{ME}: supports ruby 1.9 (much faster)"
            puts "#{ME}: you have #{RUBY_VERSION}"
        end

        # Check to see if we're running as root
        if Process.euid == 0
            puts "#{ME}: refuses to run as root"
            abort
        end

        # Some defaults for state
        logging  = true
        willfork = RUBY_PLATFORM =~ /win32/i ? false : true
        wd       = Dir.getwd

        # Do command-line options
        opts = OptionParser.new

        dd = 'Enable debug logging.'
        hd = 'Display usage information.'
        nd = 'Do not fork into the background.'
        qd = 'Disable regular logging.'
        vd = 'Display version information.'

        opts.on('-d', '--debug',   dd) { @@debug  = true  }
        opts.on('-h', '--help',    hd) { puts opts; abort }
        opts.on('-n', '--no-fork', nd) { willfork = false }
        opts.on('-q', '--quiet',   qd) { logging  = false }
        opts.on('-v', '--version', vd) { abort            }

        begin
            opts.parse(*ARGV)
        rescue OptionParser::ParseError => err
            puts err, opts
            abort
        end

        # Interpreter warnings
        $-w = true if @@debug

        # Signal handlers
        trap(:INT)   { app_exit }
        trap(:TERM)  { app_exit }
        trap(:PIPE)  { :SIG_IGN }
        trap(:CHLD)  { :SIG_IGN }
        trap(:WINCH) { :SIG_IGN }
        trap(:TTIN)  { :SIG_IGN }
        trap(:TTOU)  { :SIG_IGN }
        trap(:TSTP)  { :SIG_IGN }

        # Load configuration file - XXX
        #begin
        #    @@config = YAML.load_file('etc/config.yml')
        #rescue Exception => e
        #    puts '----------------------------'
        #    puts "#{ME}: configure error: #{e}"
        #    puts '----------------------------'
        #    abort
        #else
        #    @@config = indifferent_hash(@@config)

        #    @nickname = @@config[:nickname]

        #    if @@config[:die]
        #        puts "#{ME}: you didn't read your config..."
        #        exit
        #    end
        #end

        if @@debug
            puts "#{ME}: warning: debug mode enabled"
            puts "#{ME}: warning: everything will be logged in the clear!"
        end

        # Check to see if we're already running
        if File.exists?('var/rhubnc.pid')
            curpid = nil
            File.open('var/rhubnc.pid', 'r') { |f| curpid = f.read.chomp.to_i }

            begin
                Process.kill(0, curpid)
            rescue Errno::ESRCH, Errno::EPERM
                File.delete('var/rhubnc.pid')
            else
                puts "#{ME}: daemon is already running"
                abort
            end
        end

        # Fork into the background
        if willfork
            begin
                pid = fork
            rescue Exception => e
                puts "#{ME}: cannot fork into the background"
                abort
            end

            # This is the child process
            unless pid
                Dir.chdir(wd)
                File.umask(0)
            else # This is the parent process
                puts "#{ME}: pid #{pid}"
                puts "#{ME}: running in background mode from #{Dir.getwd}"
                abort
            end

            [$stdin, $stdout, $stderr].each { |s| s.close }

            # Set up logging
            if logging or @@debug
                self.logger = Logger.new('var/rhubnc.log', 'weekly')
            end
        else
            puts "#{ME}: pid #{Process.pid}"
            puts "#{ME}: running in foreground mode from #{Dir.getwd}"

            # Set up logging
            self.logger = Logger.new($stdout) if logging or @@debug
        end

        if @@debug
            log_level = :debug
        #else
        #    log_level = @@config[:logging].to_sym
        end

        self.log_level = log_level if logging

        # Write the PID file
        Dir.mkdir('var') unless Dir.exists?('var')
        File.open('var/rhubnc.pid', 'w') { |f| f.puts(Process.pid) }

        # Set up our handlers
        #set_event_handlers

        # Start your engines...
        Thread.abort_on_exception = true if @@debug

        #@@clients.each { |c| c.thread = Thread.new { c.io_loop } }
        #@@clients.each { |c| c.thread.join }

        # Exiting...
        app_exit

        # Return...
        self
    end

    ######
    public
    ######

    def Bouncer.config
        @@config
    end

    def Bouncer.debug
        @@debug
    end

    #######
    private
    #######

    # Converts a Hash into a Hash that allows lookup by String or Symbol
    def indifferent_hash(hash)
        # Hash.new blocks catch lookup failures
        hash = Hash.new do |hash, key|
                   hash[key.to_s] if key.is_a?(Symbol)
               end.merge(hash)

        # Look for any hashes inside the hash to convert
        hash.each do |key, value|
            # Convert this subhash
            hash[key] = indifferent_hash(value) if value.is_a?(Hash)

            # Arrays could have hashes in them
            value.each_with_index do |arval, index|
                hash[key][index] = indifferent_hash(arval) if arval.is_a?(Hash)
            end if value.is_a?(Array)
        end
    end

    def app_exit
        @logger.close if @logger
        File.delete('var/rhubnc.pid')
        exit
    end
end

