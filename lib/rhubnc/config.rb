#
# rhubnc: rhuidean-based IRC bouncer
# lib/rhubnc/config.rb: configuration DSL
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

require 'ostruct'

def configure(&block)
    Bouncer.config = Bouncer::Configuration.new
    Bouncer.config.instance_eval(&block)
    Bouncer.new 
end

class Bouncer
    @@config = nil

    def Bouncer.config; @@config; end
    def Bouncer.config=(config); @@config = config; end

    class Configuration
        attr_reader :log_level, :ssl_certificate, :ssl_private_key, :listeners, 
                    :users

        def initialize(&block)
            @log_level = :info
            @listeners = []
            @users     = []
        end

        def logging(level)
            @log_level = level.to_s
        end

        def ssl_certificate(certfile)
            @ssl_certificate = certfile.to_s
        end

        def ssl_private_key(keyfile)
            @ssl_private_key = keyfile.to_s
        end

        def listen(port, opts = {})
            listener         = OpenStruct.new
            listener.port    = port.to_i
            listener.bind_to = opts[:host] || '*'

            @listeners << listener
        end

        def user(name, &block)
            user      = OpenStruct.new
            user.name = name.to_s

            user.extend(User)
            user.instance_eval(&block)

            @users << user
        end
    end

    module User
        def password(password)
            self.password = password
        end

        def network(name, &block)
            self.networks ||= []

            net      = OpenStruct.new
            net.name = name.to_s

            net.extend(Network)
            net.instance_eval(&block)

            self.networks << net
        end
    end

    module Network
        def server(name, opts = {})
            self.servers ||= []

            serv          = OpenStruct.new
            serv.name     = name.to_s
            serv.port     = opts[:port] || 6667
            serv.password = opts[:password] if opts[:password]

            self.servers << serv
        end
    end
end

