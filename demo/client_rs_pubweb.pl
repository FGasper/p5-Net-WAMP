#!/usr/bin/env perl

package WAMP_Client;

use strict;
use warnings;
use autodie;

use FindBin;
use lib "$FindBin::Bin/../lib";

use parent qw(
    Net::WAMP::Publisher
    Net::WAMP::Subscriber
);

use JSON;

#sub on_EVENT {
#    my ($self, $msg) = @_;
#
#    #print JSON::encode_json( $msg->to_unblessed() ), $/;
#    print JSON::encode_json( $msg ), $/;
#}

#----------------------------------------------------------------------

package main;

my $host_port = $ARGV[0] or die "Need [host:]port!";
substr($host_port, 0, 0) = 'localhost:' if -1 == index($host_port, ':');

use Carp::Always;

use Net::WAMP::IO::RawSocket::Client ();

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new($host_port);
die "[$!][$@]" if !$inet;

$inet->autoflush(1);

my $wio = Net::WAMP::IO::RawSocket::Client->new( $inet, $inet );

$wio->handshake();

my $client = WAMP_Client->new( io => $wio );

$client->send_HELLO( 'com.felipe.demo' );

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper($client->handle_next_message());
print STDERR "RECEIVED …\n";

$client->send_PUBLISH(
    {},
    'com.felipe.demo.chat',
    [ $0, join(' ', @ARGV[ 1 .. $#ARGV ]) ],
);

#----------------------------------------------------------------------

1;
