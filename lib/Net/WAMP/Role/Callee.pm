package Net::WAMP::Role::Callee;

=encoding utf-8

=head1 NAME

Net::WAMP::Role::Callee

=head1 SYNOPSIS

=head1 NOTES

It is suggested that, for long-running calls,
Callee implementations C<fork()> in their C<on_INVOCATION()>, with
the child sending the response data back to the parent process.

=cut

use strict;
use warnings;

use parent qw(
    Net::WAMP::Role::Base::Client::CanError
);

use Types::Serialiser ();

use Net::WAMP::Role::Base::Client::Features ();
use Net::WAMP::RPCWorker ();

use constant {
    receiver_role_of_REGISTER => 'dealer',
    receiver_role_of_UNREGISTER => 'dealer',
    receiver_role_of_YIELD => 'dealer',

    #Only the public method has anything to do here.
    _receive_INTERRUPT => undef,

    RPCWorker_class => 'Net::WAMP::RPCWorker',
};

BEGIN {
    $Net::WAMP::Role::Base::Client::Features::FEATURES{'callee'}{'features'}{'call_canceling'} = $Types::Serialiser::true;
    $Net::WAMP::Role::Base::Client::Features::FEATURES{'callee'}{'features'}{'progressive_call_results'} = $Types::Serialiser::true;
}

#----------------------------------------------------------------------

sub send_REGISTER {
    my ($self, $opts_hr, $uri) = @_;

    my $msg = $self->_create_and_send_session_msg(
        'REGISTER',
        $opts_hr,
        $uri,
    );

    return $self->{'_sent_REGISTER'}{$msg->get('Request')} = $msg;
}

sub _receive_ERROR_REGISTER {
    my ($self, $msg) = @_;

    my $orig_msg = $self->{'_sent_REGISTER'}{$msg->get('Request')};
    if (!$orig_msg) {
        warn sprintf 'No tracked REGISTER for request ID “%s”!', $msg->get('Request');
    }

    return $orig_msg;
}

sub _receive_REGISTERED {
    my ($self, $msg) = @_;

    my $req_id = $msg->get('Request');

    my $orig_reg = delete $self->{'_sent_REGISTER'}{ $req_id };

    #This likely means the Router screwed up. Or, maybe more likely,
    #this Callee implementation has a bug … :-(
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

    my $worker_class = $self->RPCWorker_class();

    return( $procedure, $worker_class->new( $self, $msg ) );
}

#----------------------------------------------------------------------

sub send_UNREGISTER {
    my ($self, $uri) = @_;

    my $reg_id;

    for my $this_reg_id ( keys %{ $self->{'_registrations'} } ) {
        if ($uri eq $self->{'_registrations'}{$this_reg_id}) {
            $reg_id = $this_reg_id;
            last;
        }
    }

    die "No registration for procedure “$uri”!" if !$reg_id;

    my $msg = $self->_create_and_send_session_msg(
        'UNREGISTER',
        $reg_id,
    );

    return $self->{'_sent_UNREGISTER'}{$msg->get('Request')} = $msg;
}

sub _receive_ERROR_UNREGISTER {
    my ($self, $msg) = @_;

    my $orig_msg = $self->{'_sent_UNREGISTER'}{$msg->get('Request')};
    if (!$orig_msg) {
        warn sprintf 'No tracked UNREGISTER for request ID “%s”!', $msg->get('Request');
    }

    return $orig_msg;
}

sub _receive_UNREGISTERED {
    my ($self, $msg) = @_;

    my $req_id = $msg->get('Request');

    my $unreg_msg = delete $self->{'_sent_UNREGISTER'}{ $req_id } or do {
        die "Received UNREGISTERED for unknown ($req_id)!"; #XXX
    };

    my $reg = $unreg_msg->get('Registration');

    delete $self->{'_registrations'}{ $reg };

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
#sub _receive_INTERRUPT {
#    my ($self, $msg) = @_;
#
#    my $req_id = $msg->get('Request');
#
#    my $worker = delete $self->{'_invocations'}{ $req_id };
#
#    if (!$worker) {
#        die "Received INTERRUPT for unknown INVOCATION ($req_id)!";
#    }
#
#    $worker->interrupt($msg);
#
#    return;
#}

1;
