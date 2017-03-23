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
    my ($self, $io, $options, $procedure) = @_;

    if ( $self->_procedure_is_in_state($io, $procedure) ) {
        my $realm = $self->_get_realm_for_tpt($io);
        die "Already registered in “$realm”: “$procedure”";
    }

    $self->{'_state'}->set_realm_property(
        $io,
        "procedure_tpt_$procedure",
        $io,
    );

    #unused? See advanced
    $self->{'_state'}->set_realm_property(
        $io,
        "procedure_options_$procedure",
        $options,
    );

    my $registration = Protocol::WAMP::Utils::generate_global_id();

    #CALL needs to look it up this way.
    $self->{'_state'}->set_realm_property(
        $io,
        "procedure_registration_$procedure",
        $registration,
    );

    #UNREGISTER needs to look it up this way.
    $self->{'_state'}->set_realm_property(
        $io,
        "registration_procedure_$registration",
        $procedure,
    );

    return $registration;
}

sub _procedure_is_in_state {
    my ($self, $io, $procedure) = @_;

    return !!$self->{'_state'}->get_realm_property($io, "procedure_registration_$procedure");
}

sub unregister {
    my ($self, $io, $registration) = @_;

    my $procedure = $self->{'_state'}->unset_realm_property("registration_procedure_$registration");
    if (!defined $procedure) {
        my $realm = $self->_get_realm_for_tpt($io);
        die "No known procedure in “$realm” for registration “$registration”!";
    }

    for my $k (
        "procedure_tpt_$procedure",
        "procedure_options_$procedure",
        "procedure_registration_$procedure",
    ) {
        $self->{'_state'}->unset_realm_property( $io, $k );
    }

    return;
}

#sub _get_target_tpt_for_procedure {
#    my ($self, $src_tpt, $procedure) = @_;
#
#    my $realm = $self->_get_realm_for_tpt($src_tpt);
#
#    return $self->{'_realm_procedure'}{$realm}{$procedure}{'io'};
#}

#----------------------------------------------------------------------
# Subclass interface:
#
# Must implement:
#   - handle_REGISTER($msg) - responsible for send_REGISTERED()
#   - handle_UNREGISTER($msg) - must send_UNREGISTERED()
#----------------------------------------------------------------------

sub _receive_REGISTER {
    my ($self, $io, $msg) = @_;

    return $self->_catch_exception(
        $io,
        'REGISTER',
        $msg->get('Request'),
        sub {
            my ($opts, $proc) = map { $msg->get($_) } qw( Options Procedure );

            #XXX TODO
            #$self->_verify_registration_request( $realm, $opts, $proc );

            my $reg_id = $self->register($io, $opts, $proc);

            $self->_send_REGISTERED( $io, $msg->get('Request'), $reg_id );

            return $reg_id;
        },
    );
}

sub _send_REGISTERED {
    my ($self, $io, $req_id, $reg_id) = @_;

    return $self->_create_and_send_msg(
        $io,
        'REGISTERED',
        $req_id,
        $reg_id,
    );
}

sub _receive_UNREGISTER {
    my ($self, $io, $msg) = @_;

    return $self->_catch_exception(
        $io,
        'UNREGISTER',
        $msg->get('Request'),
        sub {
            $self->unregister( $io, $msg->get('Registration') );

            $self->send_UNREGISTERED( $io, $msg->get('Request') );

            return;
        },
    );

    #TODO: Need some way to handle failure & public callback:
    #   - not call?
    #   - make some indication of initial failure?
}

sub send_UNREGISTERED {
    my ($self, $io, $req_id) = @_;

    return $self->_create_and_send_msg(
        $io,
        'UNREGISTERED',
        $req_id,
    );
}

sub _receive_CALL {
    my ($self, $io, $msg) = @_;

    #TODO: validate

    my $procedure = $msg->get('Procedure') or do {
        die "Need “Procedure”!";
    };

    my $target_tpt = $self->{'_state'}->get_realm_property(
        $io,
        "procedure_tpt_$procedure",
    );

    if (!$target_tpt) {
        my $realm = $self->_get_realm_for_tpt($io);
        die "Unknown procedure “$procedure” in realm “$realm”!";
    }

    my $registration = $self->{'_state'}->get_realm_property(
        $io,
        "procedure_registration_$procedure",
    );

    my $msg2 = $self->_send_INVOCATION(
        $target_tpt,
        $registration,
        {}, #TODO: determine support
        $msg->get('Arguments'),
        $msg->get('ArgumentsKw'),
    );

    $self->{'_state'}->set_tpt_property(
        $target_tpt,
        'invocation_call_req_id_' . $msg2->get('Request'),
        $msg->get('Request'),
    );

    $self->{'_state'}->set_tpt_property(
        $target_tpt,
        'invocation_call_tpt_' . $msg2->get('Request'),
        $io,
    );

    return;
}

sub _send_INVOCATION {
    my ($self, $io, $reg_id, $details, $args_ar, $args_hr) = @_;

    return $self->_create_and_send_session_msg(
        $io,
        'INVOCATION',
        $reg_id,
        $details,
        ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
    );
}

sub _receive_YIELD {
    my ($self, $io, $msg) = @_;

    my $invoc_req_id = $msg->get('Request');

    my $orig_req_id = $self->{'_state'}->unset_tpt_property(
        $io,
        "invocation_call_req_id_$invoc_req_id",
    );

    if (!defined $orig_req_id) {
        die "Unrecognized YIELD request ID ($invoc_req_id)!"
    }

    my $orig_tpt = $self->{'_state'}->unset_tpt_property(
        $io,
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
    my ($self, $io, $req_id, $details, $args_ar, $args_hr) = @_;

    return $self->_create_and_send_msg(
        $io,
        'RESULT',
        $req_id,
        $details,
        ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
    );
}

sub _send_INTERRUPT {
}

1;
