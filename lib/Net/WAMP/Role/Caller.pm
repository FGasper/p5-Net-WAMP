package Net::WAMP::Role::Caller;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Role::Base::Client
);

use Types::Serialiser ();

use Net::WAMP::Role::Base::Client::Features ();

use constant {
    receiver_role_of_CALL => 'dealer',

    receiver_role_of_CANCEL => 'dealer',
    receiver_feature_of_CANCEL => 'call_canceling',
};

BEGIN {
    $Net::WAMP::Role::Base::Client::Features::FEATURES{'caller'}{'features'}{'call_canceling'} = $Types::Serialiser::true;
    $Net::WAMP::Role::Base::Client::Features::FEATURES{'caller'}{'features'}{'progressive_call_results'} = $Types::Serialiser::true;
}

sub send_CALL {
    my ($self, $opts_hr, $procedure, @args) = @_;

    my $msg = $self->_create_and_send_session_msg(
        'CALL',
        $opts_hr,
        $procedure,
        @args,
    );

    return $self->{'_sent_CALL'}{ $msg->get('Request') } = $msg;
}

sub _receive_RESULT {
    my ($self, $msg) = @_;

    my $orig_msg = $self->{'_sent_CALL'}{ $msg->get('Request') };

    if (!$orig_msg) {
        die sprintf("Received RESULT for unknown! (%s)", $msg->get('Request')); #XXX
    }

    if ($msg->get('Details')->{'progress'}) {
        if (!$orig_msg->get('Options')->{'receive_progress'}) {
            die sprintf("Received unrequested progressive RESULT! (%s)", $msg->get('Request')); #XXX
        }
    }
    else {
        delete $self->{'_sent_CALL'}{ $msg->get('Request') };
    }

    return;
}

#----------------------------------------------------------------------

#Requires HELLO with roles.caller.features.call_canceling of true
sub send_CANCEL {
    my ($self, $req_id, $opts_hr) = @_;

    if (!delete $self->{'_sent_CALL'}{$req_id}) {
        die sprintf("Refuse to send CANCEL for unknown! (%s)", $req_id); #XXX
    }

    return $self->_create_and_send_msg(
        'CANCEL',
        $req_id,
        $opts_hr,
    );
}

1;
