#
# rhubnc: rhuidean-based IRC bouncer
# lib/rhubnc.rb: startup routines, etc
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Check for rhuidean
begin
    require 'rhuidean'
rescue LoadError
    puts 'rhubnc: unable to load rhuidean'
    puts 'rhubnc: this library is required for IRC communication'
    puts 'rhubnc: gem install --remote rhuidean'
    abort
end

# Import required Ruby modules
%w(logger openssl optparse yaml).each { |m| require m }

# Import required application modules
%w(config server user).each { |m| require 'rhubnc/' + m }

# The main application class
class Bouncer

    ##
    # mixins
    include Loggable # Magic logging from rhuidean

    ##
    # constants

    # Project name
    ME = 'rhubnc'

    # Version number
    V_MAJOR  = 0
    V_MINOR  = 0
    V_PATCH  = 1

    VERSION  = "#{V_MAJOR}.#{V_MINOR}.#{V_PATCH}"

    ##
    # class variables

    # A list of our servers
    @@servers = []

    # The OpenSSL context used for STARTTLS
    @@ssl_context = nil

    ##
    # Create a new +Bouncer+ object, which starts and runs the entire
    # application. Everything starts and ends here.
    #
    # return:: self
    #
    def initialize
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
        debug    = false
        willfork = RUBY_PLATFORM =~ /win32/i ? false : true
        wd       = Dir.getwd
        @logger  = nil

        # Do command-line options
        opts = OptionParser.new

        dd = 'Enable debug logging.'
        hd = 'Display usage information.'
        nd = 'Do not fork into the background.'
        qd = 'Disable regular logging.'
        vd = 'Display version information.'

        opts.on('-d', '--debug',   dd) { debug  = true  }
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
        $-w = true if debug

        # Signal handlers
        trap(:INT)   { app_exit }
        trap(:TERM)  { app_exit }
        trap(:PIPE)  { :SIG_IGN }
        trap(:CHLD)  { :SIG_IGN }
        trap(:WINCH) { :SIG_IGN }
        trap(:TTIN)  { :SIG_IGN }
        trap(:TTOU)  { :SIG_IGN }
        trap(:TSTP)  { :SIG_IGN }

        # Set up the SSL stuff - XXX
        #certfile = @@config[:certificate]
        #keyfile  = @@config[:private_key]

        #begin
        #    cert = OpenSSL::X509::Certificate.new(File.read(certfile))
        #    pkey = OpenSSL::PKey::RSA.new(File.read(keyfile))
        #rescue Exception => e
        #    puts "#{ME}: configuration error: #{e}"
        #    abort
        #else
        #    ctx      = OpenSSL::SSL::SSLContext.new
        #    ctx.cert = cert
        #    ctx.key  = pkey

        #    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
        #    ctx.options     = OpenSSL::SSL::OP_NO_TICKET
        #    ctx.options    |= OpenSSL::SSL::OP_NO_SSLv2
        #    ctx.options    |= OpenSSL::SSL::OP_ALL

        #    @@ssl_context = ctx
        #end

        if debug
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
            if logging or debug
                self.logger = Logger.new('var/rhubnc.log', 'weekly')
            end
        else
            puts "#{ME}: pid #{Process.pid}"
            puts "#{ME}: running in foreground mode from #{Dir.getwd}"

            # Set up logging
            self.logger = Logger.new($stdout) if logging or debug
        end

        if debug
            log_level = :debug
        else
            log_level = @@config.log_level.to_sym
        end

        self.log_level = log_level if logging

        # Write the PID file
        Dir.mkdir('var') unless Dir.exists?('var')
        File.open('var/rhubnc.pid', 'w') { |f| f.puts(Process.pid) }

        # XXX - timers

        # Create User objects
        @@config.users.each do |user|
            User.new(user.name, user.passwd, user.flags, user.networks)
        end

        # Start the listeners
        @@config.listeners.each do |listener|
            @@servers << Server.new do |s|
                s.bind_to = listener.bind_to
                s.port    = listener.port
                s.logger  = @logger if logging
            end
        end

        # Start your engines...
        Thread.abort_on_exception = true if debug

        @@servers.each { |s| s.thread = Thread.new { s.io_loop } }
        @@servers.each { |s| s.thread.join }

        # Exiting...
        app_exit

        # Return...
        self
    end

    #######
    private
    #######

    def app_exit
        @logger.close if @logger
        File.delete('var/rhubnc.pid')
        exit
    end
end

