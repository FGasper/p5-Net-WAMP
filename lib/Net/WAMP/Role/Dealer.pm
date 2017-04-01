package Net::WAMP::Role::Dealer;

use strict;
use warnings;

use Try::Tiny;

use parent qw(
    Net::WAMP::Role::Base::Router
);

use Types::Serialiser ();

use Net::WAMP::Role::Base::Router::Features ();

BEGIN {
    $Net::WAMP::Role::Base::Router::Features::FEATURES{'dealer'}{'features'}{'call_canceling'} = $Types::Serialiser::true;
    $Net::WAMP::Role::Base::Router::Features::FEATURES{'dealer'}{'features'}{'progressive_call_results'} = $Types::Serialiser::true;
}

#----------------------------------------------------------------------

sub register {
    my ($self, $session, $options, $procedure) = @_;

    if ( $self->_procedure_is_in_state($session, $procedure) ) {
        my $realm = $self->_get_realm_for_session($session);
        die "Already registered in “$realm”: “$procedure”";
    }

    $self->{'_state'}->set_realm_property(
        $session,
        "procedure_session_$procedure",
        $session,
    );

    #unused? See advanced
    $self->{'_state'}->set_realm_property(
        $session,
        "procedure_options_$procedure",
        $options,
    );

    my $registration = Net::WAMP::Utils::generate_global_id();

    #CALL needs to look it up this way.
    $self->{'_state'}->set_realm_property(
        $session,
        "procedure_registration_$procedure",
        $registration,
    );

    #UNREGISTER needs to look it up this way.
    $self->{'_state'}->set_realm_property(
        $session,
        "registration_procedure_$registration",
        $procedure,
    );

    return $registration;
}

sub _procedure_is_in_state {
    my ($self, $session, $procedure) = @_;

    return !!$self->{'_state'}->get_realm_property($session, "procedure_registration_$procedure");
}

sub unregister {
    my ($self, $session, $registration) = @_;

    my $procedure = $self->{'_state'}->unset_realm_property("registration_procedure_$registration");
    if (!defined $procedure) {
        my $realm = $self->_get_realm_for_session($session);
        die "No known procedure in “$realm” for registration “$registration”!";
    }

    for my $k (
        "procedure_session_$procedure",
        "procedure_options_$procedure",
        "procedure_registration_$procedure",
    ) {
        $self->{'_state'}->unset_realm_property( $session, $k );
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
    my ($self, $session, $msg) = @_;

use Data::Dumper;
print STDERR Dumper $msg;

    return $self->_catch_exception(
        $session,
        'REGISTER',
        $msg->get('Request'),
        sub {
            my ($opts, $proc) = map { $msg->get($_) } qw( Options Procedure );

            #XXX TODO
            #$self->_verify_registration_request( $realm, $opts, $proc );

            my $reg_id = $self->register($session, $opts, $proc);

            $self->_send_REGISTERED( $session, $msg->get('Request'), $reg_id );

            return $reg_id;
        },
    );
}

sub _send_REGISTERED {
    my ($self, $session, $req_id, $reg_id) = @_;

    return $self->_create_and_send_msg(
        $session,
        'REGISTERED',
        $req_id,
        $reg_id,
    );
}

sub _receive_UNREGISTER {
    my ($self, $session, $msg) = @_;

    return $self->_catch_exception(
        $session,
        'UNREGISTER',
        $msg->get('Request'),
        sub {
            $self->unregister( $session, $msg->get('Registration') );

            $self->send_UNREGISTERED( $session, $msg->get('Request') );

            return;
        },
    );

    #TODO: Need some way to handle failure & public callback:
    #   - not call?
    #   - make some indication of initial failure?
}

sub send_UNREGISTERED {
    my ($self, $session, $req_id) = @_;

    return $self->_create_and_send_msg(
        $session,
        'UNREGISTERED',
        $req_id,
    );
}

sub _receive_CALL {
    my ($self, $session, $msg) = @_;

    #TODO: validate

    my $procedure = $msg->get('Procedure') or do {
        die "Need “Procedure”!";
    };

    my $target_session = $self->{'_state'}->get_realm_property(
        $session,
        "procedure_session_$procedure",
    );

    if (!$target_session) {
        my $realm = $self->_get_realm_for_session($session);
        die "Unknown procedure “$procedure” in realm “$realm”!";
    }

    my $registration = $self->{'_state'}->get_realm_property(
        $session,
        "procedure_registration_$procedure",
    );

    my $msg2 = $self->_send_INVOCATION(
        $target_session,
        $registration,
        {}, #TODO: determine support
        $msg->get('Arguments'),
        $msg->get('ArgumentsKw'),
    );

    $self->{'_state'}->set_session_property(
        $target_session,
        'invocation_call_req_id_' . $msg2->get('Request'),
        $msg->get('Request'),
    );

    $self->{'_state'}->set_session_property(
        $target_session,
        'invocation_call_session_' . $msg2->get('Request'),
        $session,
    );

    return;
}

sub _send_INVOCATION {
    my ($self, $session, $reg_id, $details, $args_ar, $args_hr) = @_;

    return $self->_create_and_send_session_msg(
        $session,
        'INVOCATION',
        $reg_id,
        $details,
        ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
    );
}

sub _receive_YIELD {
    my ($self, $session, $msg) = @_;

    my $invoc_req_id = $msg->get('Request');

    my $orig_req_id = $self->{'_state'}->unset_session_property(
        $session,
        "invocation_call_req_id_$invoc_req_id",
    );

    if (!defined $orig_req_id) {
        die "Unrecognized YIELD request ID ($invoc_req_id)!"
    }

    my $orig_session = $self->{'_state'}->unset_session_property(
        $session,
        "invocation_call_session_$invoc_req_id",
    );

    $self->_send_RESULT(
        $orig_session,
        $orig_req_id,
        {}, #TODO
        $msg->get('Arguments'),
        $msg->get('ArgumentsKw'),
    );

    return;
}

sub _send_RESULT {
    my ($self, $session, $req_id, $details, $args_ar, $args_hr) = @_;

    return $self->_create_and_send_msg(
        $session,
        'RESULT',
        $req_id,
        $details,
        ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
    );
}

sub _send_INTERRUPT {
}

1;
