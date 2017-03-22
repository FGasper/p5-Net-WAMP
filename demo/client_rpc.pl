#!/usr/bin/env perl

package WAMP_Client;

use strict;
use warnings;
use autodie;

use FindBin;
use lib "$FindBin::Bin/../lib";

use parent qw(
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

my $host_port = $ARGV[0] or die "Need [host:]port!";
substr($host_port, 0, 0) = 'localhost:' if -1 == index($host_port, ':');

use Carp::Always;

use Net::WAMP::IO::WebSocket::Client ();

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new(
    PeerAddr => $host_port,
    Blocking => 1,
);
die "[$!][$@]" if !$inet;

my $wio = Net::WAMP::IO::WebSocket::Client->new( $inet, $inet );

$wio->handshake( 'wss://demo.crossbar.io/ws', 'json' );

my $client = WAMP_Client->new( io => $wio );

$client->send_HELLO(
    'felipes_demo', #'myrealm',
);

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper($client->handle_next_message());
print STDERR "RECEIVED …\n";

#----------------------------------------------------------------------

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


1;
