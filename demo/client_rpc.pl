#!/usr/bin/env perl

package WAMP_Client;

use strict;
use warnings;
use autodie;

use FindBin;
use lib "$FindBin::Bin/../lib";

use parent qw(
    Net::WAMP::Role::Caller
    Net::WAMP::Role::Callee
);

use IO::Framed::ReadWrite::Blocking ();

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

    my $yld = $worker->yield( {}, [ $method_cr->($self, $msg) ] );

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

use Net::WAMP::RawSocket::Client ();

use IO::Socket::INET ();
#my $inet = IO::Socket::INET->new('demo.crossbar.io:80');
my $inet = IO::Socket::INET->new(
    PeerAddr => $host_port,
    Blocking => 1,
);
die "[$!][$@]" if !$inet;

my $rs = Net::WAMP::RawSocket::Client->new(
    io => IO::Framed::ReadWrite::Blocking->new( $inet ),

    #RawSocket needs this to do the handshake.
    serialization => 'json',
);

$rs->send_handshake();
$rs->verify_handshake();

#----------------------------------------------------------------------
use Carp::Always;

my $session = Net::WAMP::Session->new('json');

my $client = WAMP_Client->new(
    #serialization => 'json',
    session => $session,
);

sub _send {
    my $create_func = "send_" . shift;
    $client->$create_func(@_);
    _flush_session();

    return;
}

sub _flush_session {
    while ( my $buf = $session->shift_message_queue() ) {
        $rs->send_message($buf);
    }
}

my $got_msg;

sub _receive {
    1 until $got_msg = $rs->get_next_message();
    my $resp = $client->handle_message($got_msg->get_payload());
    _flush_session();
    return $resp;
}

_send(
    'HELLO',
    'felipes_demo', #'myrealm',
);

use Data::Dumper;
print STDERR "RECEIVING …\n";
print Dumper(_receive());
print STDERR "RECEIVED …\n";

#----------------------------------------------------------------------

_send('REGISTER', {}, 'com.myapp.sum' );

#REGISTERED
my $reg_obj = _receive();
my $reg_id = $reg_obj->get('Registration');
print Dumper($reg_obj);

_send('CALL', {}, 'com.myapp.sum', [2, 7, 3] );

#INVOCATION
print Dumper(_receive());

#RESULT
print Dumper(_receive());

#----------------------------------------------------------------------



#----------------------------------------------------------------------


1;
