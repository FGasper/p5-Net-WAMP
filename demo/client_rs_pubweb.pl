#!/usr/bin/env perl

package WAMP_Client;

use strict;
use warnings;
use autodie;

use FindBin;
use lib "$FindBin::Bin/../lib";

use parent qw(
    Net::WAMP::Role::Publisher
    Net::WAMP::Role::Subscriber
);

#----------------------------------------------------------------------

package main;

my $host_port = shift(@ARGV) or die "Need [host:]port!";
substr($host_port, 0, 0) = 'localhost:' if -1 == index($host_port, ':');

if (@ARGV < 2) {
    die "$0 [host:]port name message …\n";
}

use Carp::Always;

use Net::WAMP::Transport::RawSocket::Client ();

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new($host_port);
die "[$!][$@]" if !$inet;

$inet->autoflush(1);

my $wio = Net::WAMP::Transport::RawSocket::Client->new( $inet, $inet );

$wio->handshake();

my $client = WAMP_Client->new( transport => $wio );

$client->send_HELLO( 'com.felipe.demo' );

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper($client->handle_next_message());
print STDERR "RECEIVED …\n";

$client->send_PUBLISH(
    {},
    'com.felipe.demo.chat',
    [ shift(@ARGV), "@ARGV" ],
);

#----------------------------------------------------------------------

1;
