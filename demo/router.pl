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

use Try::Tiny;

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
die "server: [$@][$!]" if !$server;

#$server->blocking(0);

printf STDERR "server fd: %d\n", fileno($server);

use IO::Select;
my $select = IO::Select->new( $server );

my %fd_io;

my $router = MyRouter->new();

use Net::WAMP::IO::WebSocket::Server ();

#TODO handle select exception events
while (1) {
    my ($rdrs_ar, undef, $errs_ar) = IO::Select->select( $select, undef, $select );

    #TODO: heartbeat

    for my $fh (@$rdrs_ar) {
        if ($fh == $server) {
printf STDERR "accepting\n";
            accept( my $connection, $server );
printf STDERR "connection fd: %d\n", fileno($connection);

            $connection->blocking(0);
            $select->add($connection);

            $fd_io{fileno $connection} = Net::WAMP::IO::WebSocket::Server->new( ($connection) x 2 );
        }

        #A successful WS connection creates an IO object.
        elsif (my $io = $fd_io{fileno $fh}) {
printf STDERR "////// reading fd %d ($io)\n", fileno $fh;
            if ($io->did_handshake()) {
print STDERR "reading wamp\n";
                my $msg;
                try {
                    $msg = $io->read_wamp_message();
                }
                catch {
                    my $done = try { $_->isa('Net::WAMP::X::EmptyRead') };
                    $done ||= try { $_->isa('Net::WebSocket::X::ReceivedClose') };

                    if ($done) {
printf STDERR "////// REMOVING FD %d $io\n", fileno($fh);
use Data::Dumper;
#print STDERR Dumper $router->{'_state'};
                        $router->forget_io($io);
print STDERR "=\n=\n=\n=\n=\n=\n=\n=\n";
#print STDERR Dumper $router->{'_state'};
                        $select->remove($fh);
                        delete $fd_io{fileno $fh};
                        close $fh;
                    }
                    else {
                        local $@ = $_;
                        die;
                    }
                };

                if ($msg) {
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

    for my $fh ( @$errs_ar ) {
        printf STDERR "FD %d error!\n", fileno($fh);
        $select->remove($fh);
        close $fh;
    }
}

1;
