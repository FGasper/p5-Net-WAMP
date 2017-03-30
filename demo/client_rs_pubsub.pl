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

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new($host_port);
die "[$!][$@]" if !$inet;

$inet->autoflush(1);

use IO::Framed::Blocking ();

use Net::WAMP::RawSocket::Client ();

my $rs = Net::WAMP::RawSocket::Client->new(
    io => IO::Framed::Blocking->new( $inet, $inet ),
    serialization => 'json',
);

use Carp::Always;

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

_send( 'HELLO', 'felipes_demo', ); #'myrealm',

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper(_receive());
print STDERR "RECEIVED …\n";

#----------------------------------------------------------------------

_send( 'SUBSCRIBE', {}, 'com.myapp.hello' );
print STDERR "sent subscribe\n";
print Dumper(_receive());

use Types::Serialiser ();
_send(
    'PUBLISH',
    {
        acknowledge => Types::Serialiser::true(),
        exclude_me => Types::Serialiser::false(),
    },
    'com.myapp.hello',
    ['Hello, world! This is my published message.'],
);

#EVENT
print Dumper(_receive());

#PUBLISHED
print Dumper(_receive());

#----------------------------------------------------------------------

1;
