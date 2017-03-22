package Net::WAMP::IO::CheckSocket;

use strict;
use warnings;

use Socket ();

use Net::WAMP::IO::RawSocket::Constants ();

sub is_rawsocket {
    my ($socket) = @_;

    my $byte1 = recv( $socket, my $buf, 1, Socket::MSG_PEEK() );

    return ord($byte1) == Net::WAMP::IO::RawSocket::Constants::MAGIC_FIRST_OCTET();
}

1;
