#
# rhubnc: rhuidean-based IRC bouncer
# lib/rhubnc/client.rb: represents a connected client
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(digest/md5 openssl).each { |m| require m } # XXX - SSL

class Client

    ##
    # mixins
    include Loggable

    ##
    # instance attributes
    attr_reader :host, :resource, :socket

    ##
    # XXX
    def initialize(host, socket)
        # The hostname our client connected to
        @connect_host = nil

        # Is our socket dead?
        @dead = false

        # Our event queue
        @eventq = IRC::EventQueue.new

        # Our hostname
        @host = host

        # Our Logger object
        @logger     = nil
        self.logger = nil

        # Received data waiting to be parsed
        @recvq = []

        # Data waiting to be sent
        @sendq = []

        # Our socket
        @socket = socket

        # Our DB user object
        @user = nil

        # If we have a block let it set up our instance attributes
        yield(self) if block_given?

        # Set up event handlers
        set_default_handlers

        log(:debug, "new client from #@host")

        # XXX - make this pretty
        @sendq << "NOTICE AUTH :*** Welcome to the bouncer. Authenticate."

        self
    end

    #######
    private
    #######

    def set_default_handlers
        @eventq.handle(:recvq_ready) { parse }
        @eventq.handle(:QUIT) { self.dead = true }

        @eventq.handle(:BNC) do |m|
            next unless m.params

            cmd = "BNC_#{m.params[0].upcase}".to_sym
            @eventq.post(cmd, m)
        end

        @eventq.handle(:BNC_AUTH) { |m| do_auth(m) }
    end

    def do_auth(m)
        username = m.params[1]
        password = m.params[2]

        unless user = User.find(username)
            log(:info, "failed auth attempt to unknown user #{username}")
            self.dead = true
            return
        end

        if user.authenticate(password)
            @user = user
            log(:info, "#{username} successfully authenticated")
            @sendq << "NOTICE AUTH :*** You have authenticated as #{username}."
        else
            log(:info, "failed auth attempt to #{username}")
            self.dead = true
        end
    end

    def parse
        while line = @recvq.shift
            line.chomp!
            log(:debug,"-> #{line}")

            return if line.empty?

            command = line.split(' ')
            params  = command[1 .. -1]
            command = command[0].upcase.to_sym

            unless @eventq.handlers[command]
                # No handler means we toss it to IRC - XXX
                return
            end

            msg = IRC::Message.new(self, line, nil, nil, params)

            @eventq.post(command, msg)
        end
    end

    #
    # Takes care of setting some stuff when we die.
    # ---
    # bool:: +true+ or +false+
    # returns:: +nil+
    #
    def dead=(bool)
        if bool
            # Try to flush the sendq first. This is for errors and such.
            write unless @sendq.empty?

            log(:info, "client from #@host disconnected")

            @socket.close
            @socket = nil
            @dead   = true
            @state  = []
        end
    end

    ######
    public
    ######

    def need_write?
        @sendq.empty? ? false : true
    end

    def has_events?
        @eventq.needs_ran?
    end

    def run_events
        @eventq.run
    end

    def dead?
        @dead
    end

    #
    # Called when we're ready to read.
    # ---
    # returns:: +self+
    #
    def read
        begin
            ret = @socket.read_nonblock(8192)
        rescue IO::WaitReadable
            retry
        rescue Exception => e
            ret = nil # Dead
        end

        if not ret or ret.empty?
            log(:info, "error from #@host: #{e}") if e
            self.dead = true
            return
        end

        # This passes every "line" to our block, including the "\n".
        ret.scan(/(.+\n?)/) do |line|
            line = line[0]

            # If the last line had no \n, add this one onto it.
            if @recvq[-1] and @recvq[-1][-1].chr != "\n"
                @recvq[-1] += line
            else
                @recvq << line
            end
        end

        if @recvq[-1] and @recvq[-1][-1].chr == "\n"
            @eventq.post(:recvq_ready)
        end

        self
    end

    ##
    # Called when we're ready to write.
    # ---
    # returns:: +self+
    #
    def write
        # Use shift because we need it to fall off immediately.
        while line = @sendq.shift
            begin
                line += "\r\n"
                @socket.write_nonblock(line)
            rescue IO::WaitReadable
                retry
            rescue Exception
                self.dead = true
                return
            else
                log(:debug, "<- #{line[0 ... -2]}")
            end
        end
    end
end

