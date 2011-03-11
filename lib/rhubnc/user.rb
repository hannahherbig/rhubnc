#
# rhubnc: rhuidean-based IRC bouncer
# lib/rhubnc/user.rb: user objects
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#

class User

    ##
    # constants
    SALT_CHARS = '0123456789' +
                 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' +
                 'abcdefghijklmnopqrstuvwxyz' +
                 './'

    ##
    # class variables

    # A list of all users
    @@users = []

    ##
    # instance variables
    attr_reader :name, :networks

    def initialize(name, password, flags, networks)
        @name     = name
        @password = password
        @networks = networks

        if flags.is_a?(Array)
            @flags = flags
        elsif flags
            @flags = [flags]
        else
            @flags = nil
        end

        @@users << self
    end

    ######
    public
    ######

    def User.find(name)
        @@users.find { |u| u.name == name }
    end

    #
    # Given a plaintext password, compare to configured password.
    # ---
    # password:: plaintext password to compare
    # returns:: +true+ or +false+
    #
    def authenticate(password)
        salt = @password[0 ... 2]
        encr = password.crypt(salt)

        encr == @password
    end

    def operator?
        @flags.include?(:operator)
    end

    #
    # Given a plaintext password, encrypt and change configured password.
    # ---
    # password:: plaintext password to encrypt and set
    # returns:: encrypted password
    #
    def password=(password)
       salt  = SALT_CHARS[rand(SALT_CHARS.length)]
       salt += SALT_CHARS[rand(SALT_CHARS.length)]

       @password = password.crypt(salt)
    end
end

