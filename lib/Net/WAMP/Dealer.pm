package Net::WAMP::Dealer;

use strict;
use warnings;

use Try::Tiny;

use parent qw(
    Net::WAMP::Router
    Net::WAMP::SessionScope
);

use Types::Serialiser ();

use Net::WAMP::Router::Features ();

BEGIN {
    $Net::WAMP::Router::Features::FEATURES{'dealer'}{'features'}{'call_canceling'} = $Types::Serialiser::true;
    $Net::WAMP::Router::Features::FEATURES{'dealer'}{'features'}{'progressive_call_results'} = $Types::Serialiser::true;
}

#----------------------------------------------------------------------

sub register {
    my ($self, $tpt, $options, $procedure) = @_;

    if ( $self->_procedure_is_in_state($tpt, $procedure) ) {
        my $realm = $self->_get_realm_for_tpt($tpt);
        die "Already registered in “$realm”: “$procedure”";
    }

    $self->{'_state'}->set_realm_property(
        $tpt,
        "procedure_tpt_$procedure",
        $tpt,
    );

    #unused? See advanced
    $self->{'_state'}->set_realm_property(
        $tpt,
        "procedure_options_$procedure",
        $options,
    );

    my $registration = Protocol::WAMP::Utils::generate_global_id();

    #CALL needs to look it up this way.
    $self->{'_state'}->set_realm_property(
        $tpt,
        "procedure_registration_$procedure",
        $registration,
    );

    #UNREGISTER needs to look it up this way.
    $self->{'_state'}->set_realm_property(
        $tpt,
        "registration_procedure_$registration",
        $procedure,
    );

    return $registration;
}

sub _procedure_is_in_state {
    my ($self, $tpt, $procedure) = @_;

    return !!$self->{'_state'}->get_realm_property($tpt, "procedure_registration_$procedure");
}

sub unregister {
    my ($self, $tpt, $registration) = @_;

    my $procedure = $self->{'_state'}->unset_realm_property("registration_procedure_$registration");
    if (!defined $procedure) {
        my $realm = $self->_get_realm_for_tpt($tpt);
        die "No known procedure in “$realm” for registration “$registration”!";
    }

    for my $k (
        "procedure_tpt_$procedure",
        "procedure_options_$procedure",
        "procedure_registration_$procedure",
    ) {
        $self->{'_state'}->unset_realm_property( $tpt, $k );
    }

    return;
}

#----------------------------------------------------------------------
# Subclass interface:
#
# Must implement:
#   - handle_REGISTER($msg) - responsible for send_REGISTERED()
#   - handle_UNREGISTER($msg) - must send_UNREGISTERED()
#----------------------------------------------------------------------

sub _receive_REGISTER {
    my ($self, $tpt, $msg) = @_;

    return $self->_catch_exception(
        $tpt,
        'REGISTER',
        $msg->get('Request'),
        sub {
            my ($opts, $proc) = map { $msg->get($_) } qw( Options Procedure );

            #XXX TODO
            #$self->_verify_registration_request( $realm, $opts, $proc );

            my $reg_id = $self->register($tpt, $opts, $proc);

            $self->_send_REGISTERED( $tpt, $msg->get('Request'), $reg_id );

            return $reg_id;
        },
    );
}

sub _send_REGISTERED {
    my ($self, $tpt, $req_id, $reg_id) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'REGISTERED',
        $req_id,
        $reg_id,
    );
}

sub _receive_UNREGISTER {
    my ($self, $tpt, $msg) = @_;

    return $self->_catch_exception(
        $tpt,
        'UNREGISTER',
        $msg->get('Request'),
        sub {
            $self->unregister( $tpt, $msg->get('Registration') );

            $self->send_UNREGISTERED( $tpt, $msg->get('Request') );

            return;
        },
    );

    #TODO: Need some way to handle failure & public callback:
    #   - not call?
    #   - make some indication of initial failure?
}

sub send_UNREGISTERED {
    my ($self, $tpt, $req_id) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'UNREGISTERED',
        $req_id,
    );
}

sub _receive_CALL {
    my ($self, $tpt, $msg) = @_;

    #TODO: validate

    my $procedure = $msg->get('Procedure') or do {
        die "Need “Procedure”!";
    };

    my $target_tpt = $self->{'_state'}->get_realm_property(
        $tpt,
        "procedure_tpt_$procedure",
    );

    if (!$target_tpt) {
        my $realm = $self->_get_realm_for_tpt($tpt);
        die "Unknown procedure “$procedure” in realm “$realm”!";
    }

    my $registration = $self->{'_state'}->get_realm_property(
        $tpt,
        "procedure_registration_$procedure",
    );

    my $msg2 = $self->_send_INVOCATION(
        $target_tpt,
        $registration,
        {}, #TODO: determine support
        $msg->get('Arguments'),
        $msg->get('ArgumentsKw'),
    );

    $self->{'_state'}->set_transport_property(
        $target_tpt,
        'invocation_call_req_id_' . $msg2->get('Request'),
        $msg->get('Request'),
    );

    $self->{'_state'}->set_transport_property(
        $target_tpt,
        'invocation_call_tpt_' . $msg2->get('Request'),
        $tpt,
    );

    return;
}

sub _send_INVOCATION {
    my ($self, $tpt, $reg_id, $details, $args_ar, $args_hr) = @_;

    return $self->_create_and_send_session_msg(
        $tpt,
        'INVOCATION',
        $reg_id,
        $details,
        ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
    );
}

sub _receive_YIELD {
    my ($self, $tpt, $msg) = @_;

    my $invoc_req_id = $msg->get('Request');

    my $orig_req_id = $self->{'_state'}->unset_transport_property(
        $tpt,
        "invocation_call_req_id_$invoc_req_id",
    );

    if (!defined $orig_req_id) {
        die "Unrecognized YIELD request ID ($invoc_req_id)!"
    }

    my $orig_tpt = $self->{'_state'}->unset_transport_property(
        $tpt,
        "invocation_call_tpt_$invoc_req_id",
    );

    $self->_send_RESULT(
        $orig_tpt,
        $orig_req_id,
        {}, #TODO
        $msg->get('Arguments'),
        $msg->get('ArgumentsKw'),
    );

    return;
}

sub _send_RESULT {
    my ($self, $tpt, $req_id, $details, $args_ar, $args_hr) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'RESULT',
        $req_id,
        $details,
        ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
    );
}

sub _send_INTERRUPT {
}

1;
