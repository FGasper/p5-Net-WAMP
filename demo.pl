#!/usr/bin/env perl

package WAMP_Client;

use strict;
use warnings;
use autodie;

use FindBin;
use lib "$FindBin::Bin/lib";

use parent qw(
    Net::WAMP::Subscriber
    Net::WAMP::Publisher
    Net::WAMP::Caller
    Net::WAMP::Callee
);

use JSON;

#sub on_EVENT {
#    my ($self, $msg) = @_;
#
#    #print JSON::encode_json( $msg->to_unblessed() ), $/;
#    print JSON::encode_json( $msg ), $/;
#}

sub on_INVOCATION {
    my ($self, $msg, $procedure, $worker) = @_;

    my $proc_snake = $procedure;
    $proc_snake =~ tr<.><_>;

    my $method_cr = $self->can("RPC_$proc_snake");
    if (!$method_cr) {
        die "Unknown RPC procedure: “$procedure”";
    }

    $worker->yield( {}, [ $method_cr->($self, $msg) ] );

    return;
}

sub RPC_com_myapp_sum {
    my ($self, $msg, $worker) = @_;

    my $sum = 0;
    $sum += $_ for @{ $msg->get('Arguments') };

    return $sum;
}

#----------------------------------------------------------------------

package main;

use Carp::Always;

use Net::WAMP::IO::WebSocket::Client ();

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new('127.0.0.1:9090');
die "[$!][$@]" if !$inet;

$inet->autoflush(1);

my $wio = Net::WAMP::IO::WebSocket::Client->new( $inet, $inet );

my $client = WAMP_Client->new( io => $wio );

$wio->handshake( 'wss://demo.crossbar.io/ws', $client->get_serialization_format(), $client->get_websocket_message_type() );

$client->send_HELLO(
    'realm_felipe', #'myrealm',
);

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper($client->handle_next_message());
print STDERR "RECEIVED …\n";

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

$client->send_REGISTER( {}, 'com.myapp.sum' );

#REGISTERED
my $reg_obj = $client->handle_next_message();
my $reg_id = $reg_obj->get('Registration');
print Dumper($reg_obj);

$client->send_CALL( {}, 'com.myapp.sum', [2, 7, 3] );

#INVOCATION
print Dumper($client->handle_next_message());

#RESULT
print Dumper($client->handle_next_message());

#----------------------------------------------------------------------



#----------------------------------------------------------------------


#----------------------------------------------------------------------

package Sub::Finally;

sub new {
    return bless [ $_[1] ], $_[0];
}

sub DESTROY {
    $_[0][0]->();
}

1;
