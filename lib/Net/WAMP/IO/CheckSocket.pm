package Net::WAMP::IO::CheckSocket;

use strict;
use warnings;

use Socket ();

use Net::WAMP::IO::RawSocket::Constants ();

sub is_rawsocket {
    my ($socket) = @_;

    local $!;

    my $buf;

    my $ok = recv( $socket, $buf, 1, Socket::MSG_PEEK() );
    if (!defined $ok) {
        die "recv() error: $!" if $!; #XXX
        die "Empty recv()!";
    };

    return ord($buf) == Net::WAMP::IO::RawSocket::Constants::MAGIC_FIRST_OCTET();
}

1;
