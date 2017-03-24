package Net::WAMP::Callee;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Client::CanError
    Net::WAMP::SessionScope
);

use Types::Serialiser ();

use Net::WAMP::Client::Features ();
use Net::WAMP::RPCWorker ();

use constant {
    receiver_role_of_REGISTER => 'dealer',
    receiver_role_of_UNREGISTER => 'dealer',
    receiver_role_of_YIELD => 'dealer',
};

BEGIN {
    $Net::WAMP::Client::Features::FEATURES{'callee'}{'features'}{'call_canceling'} = $Types::Serialiser::true;
    $Net::WAMP::Client::Features::FEATURES{'callee'}{'features'}{'progressive_call_results'} = $Types::Serialiser::true;
}

sub send_REGISTER {
    my ($self, $opts_hr, $uri) = @_;

    my $msg = $self->_create_and_send_session_msg(
        'REGISTER',
        $opts_hr,
        $uri,
    );

    return $self->{'_sent_REGISTER'}{$msg->get('Request')} = $msg;
}

sub _receive_REGISTERED {
    my ($self, $msg) = @_;

    my $req_id = $msg->get('Request');

    my $orig_reg = delete $self->{'_sent_REGISTER'}{ $req_id };

    if (!$orig_reg) {
        die "Received REGISTERED for unknown (Request=$req_id)!"; #XXX
    }

    $self->{'_registrations'}{ $msg->get('Registration') } = $orig_reg->get('Procedure');

    return;
}

#----------------------------------------------------------------------

sub _receive_INVOCATION {
    my ($self, $msg) = @_;

    my $procedure = $self->{'_registrations'}{ $msg->get('Registration') };

    if (!length $procedure) {
        my $reg_id = $msg->get('Registration');
        die "Received INVOCATION for unknown (Registration=$reg_id)!"; #XXX
    }

    $self->{'_invocations'}{ $msg->get('Request') } = $msg;

    return( $procedure, Net::WAMP::RPCWorker->new( $self, $msg ) );
}

#----------------------------------------------------------------------

sub send_UNREGISTER {
    my ($self, $opts_hr, $uri) = @_;

    my $msg = $self->_create_and_send_session_msg(
        'UNREGISTER',
        $opts_hr,
        $uri,
    );

    return $self->{'_sent_UNREGISTER'}{$msg->get('Request')} = $msg;
}

sub _receive_UNREGISTERED {
    my ($self, $msg) = @_;

    my $req_id = $msg->get('Request');

    if ( !delete $self->{'_sent_UNREGISTER'}{ $req_id }) {
        die "Received UNREGISTERED for unknown!"; #XXX
    }

    delete $self->{'_registrations'}{ $msg->get('Registration') };

    return;
}

#----------------------------------------------------------------------

sub send_YIELD {
    my ($self, $req_id, $opts_hr, @args) = @_;

    my $worker = $self->{'_invocations'}{ $req_id };
    if (!$worker) {
        die sprintf("Refuse to send YIELD for unknown INVOCATION (%s)!", $req_id);
    }

    if (!$opts_hr->{'progress'}) {
        delete $self->{'_invocations'}{ $req_id };
    }

    return $self->_create_and_send_msg(
        'YIELD',
        $req_id,
        $opts_hr,
        @args
    );
}

sub send_ERROR {
    my ($self, $req_id, $details_hr, $err_uri, @args) = @_;

    if (!delete $self->{'_invocations'}{ $req_id }) {
        die sprintf("Refuse to send ERROR for unknown INVOCATION (%s)!", $req_id);
    }

    return $self->_create_and_send_ERROR(
        'INVOCATION',
        $req_id,
        $details_hr,
        $err_uri,
        @args,
    );
}

#----------------------------------------------------------------------

#Requires HELLO with roles.callee.features.call_canceling of true
sub _receive_INTERRUPT {
    my ($self, $msg) = @_;

    my $req_id = $msg->get('Request');

    my $worker = delete $self->{'_invocations'}{ $req_id };

    if (!$worker) {
        die "Received INTERRUPT for unknown INVOCATION ($req_id)!";
    }

    $worker->interrupt($msg);

    return;
}

1;
