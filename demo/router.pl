#!/usr/bin/env perl

#----------------------------------------------------------------------
package MyRouter;

use FindBin;
use lib "$FindBin::Bin/../lib";

use parent qw(
    Net::WAMP::Dealer
    Net::WAMP::Broker
);

#----------------------------------------------------------------------
package main;

use strict;
use warnings;
use autodie;

my ($ip, $port);

if ( my $ip_port = $ARGV[0] ) {

    ($ip, $port) = $ip_port =~ m<(.+:)?([0-9]+)>;
}

die "Need [ip:]port!" if !$port;

use IO::Socket::INET;
my $server = IO::Socket::INET->new(
    LocalAddr => $ip,
    LocalPort => $port,
    Listen => 5,
    ReuseAddr => 1,
);

$server->blocking(0);

printf STDERR "server fd: %d\n", fileno($server);

use IO::Select;
my $select = IO::Select->new( $server );

my %fd_io;

my $router = MyRouter->new();

use Net::WAMP::IO::WebSocket::Server ();

#TODO handle select exception events
while (my @ready = $select->can_read()) {
    for my $fh (@ready) {
        if ($fh == $server) {
            accept( my $connection, $server );
printf STDERR "connection fd: %d\n", fileno($connection);

            $connection->blocking(0);
            $select->add($connection);

            $fd_io{fileno $connection} = Net::WAMP::IO::WebSocket::Server->new( ($connection) x 2 );
        }

        #A successful WS connection creates an IO object.
        elsif (my $io = $fd_io{fileno $fh}) {
            if ($io->did_handshake()) {
                if (my $msg = $io->read_wamp_message()) {
                    $router->route_message($msg, $io);
                }
            }
            else {
                $io->handshake();
            }
        }

        #No IO object? Then something’s wrong!
        else {
            die sprintf("Unknown read ($fh, fd %d)\n", fileno $fh);
        }
    }
}

1;
