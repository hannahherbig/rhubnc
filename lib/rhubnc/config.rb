#
# rhubnc: rhuidean-based IRC bouncer
# lib/rhubnc/config.rb: configuration DSL
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#

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
        attr_reader :log_level, :ssl_certfile, :ssl_keyfile, :listeners,
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
            @ssl_certfile = certfile.to_s
        end

        def ssl_private_key(keyfile)
            @ssl_keyfile = keyfile.to_s
        end

        def listen(port, host = '*')
            listener         = OpenStruct.new
            listener.port    = port.to_i
            listener.bind_to = host.to_s

            @listeners << listener
        end

        def user(name, opts = {}, &block)
            user       = OpenStruct.new
            user.name  = name.to_s
            user.flags = opts[:flags]

            user.extend(ConfigUser)
            user.instance_eval(&block)

            @users << user
        end
    end

    module ConfigUser
        def password(password)
            self.passwd = password
        end

        def network(name, &block)
            self.networks ||= []

            net      = OpenStruct.new
            net.name = name.to_s

            net.extend(ConfigNetwork)
            net.instance_eval(&block)

            self.networks << net
        end
    end

    module ConfigNetwork
        def server(name, port = 6667, pass = nil)
            self.servers ||= []

            serv          = OpenStruct.new
            serv.name     = name.to_s

            if port.is_a?(Hash)
                serv.port     = port[:port] || 6667
                serv.password = port[:password]
            elsif port.is_a?(Fixnum)
                serv.port = port
            end

            if pass.is_a?(Hash)
                serv.port   ||= pass[:port]
                serv.password = pass[:password]
            elsif pass.is_a?(String)
                serv.password = pass
            end

            self.servers << serv
        end
    end
end

