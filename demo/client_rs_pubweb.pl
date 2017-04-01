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

use IO::Framed::ReadWrite::Blocking ();

use Net::WAMP::RawSocket::Client ();

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new($host_port);
die "[$!][$@]" if !$inet;

$inet->autoflush(1);

my $rs = Net::WAMP::RawSocket::Client->new(
    io => IO::Framed::ReadWrite::Blocking->new( $inet ),
    serialization => 'json',
);

print STDERR "send hs\n";
$rs->send_handshake();
print STDERR "sent hs\n";
$rs->verify_handshake();
print STDERR "vf hs\n";

my $client = WAMP_Client->new(
    serialization => 'json',
);

sub _send {
    my $create_func = "send_" . shift;
    $rs->send_message( $client->message_object_to_bytes( $client->$create_func(@_) ) );

    return;
}

my $got_msg;

sub _receive {
    1 until $got_msg = $rs->get_next_message();
    return $client->handle_message($got_msg->get_payload());
}

_send( 'HELLO', 'com.felipe.demo' );

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper(_receive());
print STDERR "RECEIVED …\n";

_send(
    'PUBLISH',
    {},
    'com.felipe.demo.chat',
    [ shift(@ARGV), "@ARGV" ],
);

#----------------------------------------------------------------------

1;
