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

use IO::Framed::ReadWrite::Blocking ();

use Net::WAMP::RawSocket::Client ();

my $rs = Net::WAMP::RawSocket::Client->new(
    io => IO::Framed::ReadWrite::Blocking->new( $inet ),
);

use Carp::Always;

print STDERR "send hs\n";
$rs->send_handshake( serialization => 'json' );
print STDERR "sent hs\n";
$rs->verify_handshake();
print STDERR "vf hs\n";

my $client = WAMP_Client->new(
    serialization => 'json',
    on_send => sub { $rs->send_message($_[0]) },
);

my $got_msg;

sub _receive {
    $got_msg = $rs->get_next_message();
    return $client->handle_message($got_msg->get_payload());
}

$client->send_HELLO( 'felipes_demo' ); #'myrealm',

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper(_receive());
print STDERR "RECEIVED …\n";

#----------------------------------------------------------------------

$client->send_SUBSCRIBE( {}, 'com.myapp.hello' );
print STDERR "sent subscribe\n";
print Dumper(_receive());

use Types::Serialiser ();
$client->send_PUBLISH(
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
