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

use Net::WAMP::Transport::RawSocket::Client ();

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new($host_port);
die "[$!][$@]" if !$inet;

$inet->autoflush(1);

my $wio = Net::WAMP::Transport::RawSocket::Client->new( $inet, $inet );

$wio->handshake();

my $client = WAMP_Client->new( io => $wio );

$client->send_HELLO(
    'felipes_demo', #'myrealm',
);

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper($client->handle_next_message());
print STDERR "RECEIVED …\n";

#----------------------------------------------------------------------

$client->send_SUBSCRIBE( {}, 'com.myapp.hello' );
print STDERR "sent subscribe\n";
print Dumper($client->handle_next_message());

use Types::Serialiser ();
$client->send_PUBLISH(
    {
        acknowledge => Types::Serialiser::true(),
        exclude_me => Types::Serialiser::false(),
    },
    'com.myapp.hello',
    ['Hello, world! This is my published message.'],
);

#PUBLISHED
print Dumper($client->handle_next_message());

#EVENT
print Dumper($client->handle_next_message());

#----------------------------------------------------------------------

1;
