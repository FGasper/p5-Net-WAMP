package Net::WAMP::Role::Dealer;

use strict;
use warnings;

use Try::Tiny;

use parent qw(
    Net::WAMP::Role::Base::Router
);

use Types::Serialiser ();

use Net::WAMP::Role::Base::Router::Features ();
use Net::WAMP::X ();

BEGIN {
    $Net::WAMP::Role::Base::Router::Features::FEATURES{'dealer'}{'features'}{'call_canceling'} = $Types::Serialiser::true;
    $Net::WAMP::Role::Base::Router::Features::FEATURES{'dealer'}{'features'}{'progressive_call_results'} = $Types::Serialiser::true;
}

#----------------------------------------------------------------------

sub register {
    my ($self, $session, $options, $procedure) = @_;

    $self->_validate_uri($procedure);

    if ( $self->_procedure_is_in_state($session, $procedure) ) {
        my $realm = $self->_get_realm_for_session($session);
        die Net::WAMP::X->create('ProcedureAlreadyExists', $realm, $procedure);
    }

    #XXX: It’s less than ideal to store an actual Perl object in _state
    #because it more or less ties us to the in-memory datastore.
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

    my $procedure = $self->{'_state'}->unset_realm_property($session, "registration_procedure_$registration");
    if (!defined $procedure) {
        my $realm = $self->_get_realm_for_session($session);
        die Net::WAMP::X->create('NoSuchRegistration', $realm, $registration);
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

    return $self->_catch_exception(
        $session,
        'REGISTER',
        $msg->get('Request'),
        sub {
            my ($opts, $proc) = map { $msg->get($_) } qw( Options Procedure );

            #XXX TODO
            #$self->_verify_registration_request( $realm, $opts, $proc );

            my $reg_id;
            try {
                $reg_id = $self->register($session, $opts, $proc);
                $self->_send_REGISTERED( $session, $msg->get('Request'), $reg_id );
            }
            catch {
                if ( try { $_->isa('Net::WAMP::X::ProcedureAlreadyExists') } ) {
                    $self->_create_and_send_ERROR(
                        $session,
                        'REGISTER',
                        $msg->get('Request'),
                        {
                            net_wamp_message => $_->get_message(),
                        },
                        'wamp.error.procedure_already_exists',
                    );
                }
                elsif ( try { $_->isa('Net::WAMP::X::BadURI') } ) {
                    $self->_create_and_send_ERROR(
                        $session,
                        'REGISTER',
                        $msg->get('Request'),
                        {
                            net_wamp_message => $_->get_message(),
                        },
                        'wamp.error.invalid_uri',
                    );
                }
                else {
                    local $@ = $_;
                    die;
                }
            };

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

    $self->_catch_exception(
        $session,
        'UNREGISTER',
        $msg->get('Request'),
        sub {

            try {
                $self->unregister( $session, $msg->get('Registration') );
                $self->send_UNREGISTERED( $session, $msg->get('Request') );
            }
            catch {
                if ( try { $_->isa('Net::WAMP::X::NoSuchRegistration') } ) {
                    $self->_create_and_send_ERROR(
                        $session,
                        'UNREGISTER',
                        $msg->get('Request'),
                        {
                            net_wamp_message => $_->get_message(),
                        },
                        'wamp.error.no_such_registration',
                    );
                }
                else {
                    local $@ = $_;
                    die;
                }
            };
        },
    );

    return;
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

    return if !$self->_validate_uri_or_send_ERROR(
        $procedure,
        $session,
        'CALL',
        $msg->get('Request'),
    );

    my $target_session = $self->{'_state'}->get_realm_property(
        $session,
        "procedure_session_$procedure",
    );

    if (!$target_session) {
        $self->_create_and_send_ERROR(
            $session,
            'CALL',
            $msg->get('Request'),
            {},
            'wamp.error.no_such_procedure',
        );
        return;
    }

    my $registration = $self->{'_state'}->get_realm_property(
        $session,
        "procedure_registration_$procedure",
    );

    my $msg2 = $self->_send_INVOCATION(
        $target_session,
        $registration,
        $msg->get('Metadata'),
        $msg->get('Arguments'),
        $msg->get('ArgumentsKw'),
    );

    $self->{'_state'}->set_session_property(
        $target_session,
        'invocation_call_req_id_' . $msg2->get('Request'),
        $msg->get('Request'),
    );

    #XXX: It’s less than ideal to store an actual Perl object in _state
    #because it more or less ties us to the in-memory datastore.
    $self->{'_state'}->set_session_property(
        $target_session,
        'invocation_call_session_' . $msg2->get('Request'),
        $session,
    );

    #Used for CANCEL--------------------------------------------------
    $self->{'_state'}->set_session_property(
        $session,
        'call_invocation_req_id_' . $msg->get('Request'),
        $msg2->get('Request'),
    );

    #XXX: It’s less than ideal to store an actual Perl object in _state
    #because it more or less ties us to the in-memory datastore.
    $self->{'_state'}->set_session_property(
        $session,
        'call_invocation_session_' . $msg->get('Request'),
        $target_session,
    );
    #-----------------------------------------------------------------

    return;
}

sub _clear_call_invocation {
    my ($self, $session, $orig_req_id) = @_;

    my $target_session = $self->{'_state'}->unset_session_property(
        $session,
        "call_invocation_session_$orig_req_id",
    );

    my $target_req_id = $self->{'_state'}->unset_session_property(
        $session,
        "call_invocation_req_id_$orig_req_id",
    );

    return ($target_req_id, $target_session);
}

#As of now, only a Dealer can receive an ERROR, so there’s no risk of
#conflict with Broker.
sub _receive_ERROR_INVOCATION {
    my ($self, $session, $msg) = @_;

    my $invoc_req_id = $msg->get('Request');

    my ($orig_req_id, $orig_session) = $self->_get_invocation_call_req_and_session(
        'unset_session_property',
        $session,
        $invoc_req_id,
    );

    if ($orig_req_id) {
        $self->_clear_call_invocation($orig_session, $orig_req_id);

        $self->_create_and_send_ERROR(
            $orig_session,
            'CALL',
            $orig_req_id,
            ( map { $msg->get($_) } qw( Metadata Error Arguments ArgumentsKw ) ),
        );
    }
    elsif ($msg->{'Error'} ne 'wamp.error.canceled') {
        die "ERROR/INVOCATION (not wamp.error.canceled) that references a CALL we don’t have in state!";   #XXX drop connection? protocol error
    }

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

sub _get_invocation_call_req_and_session {
    my ($self, $access_method, $session, $invoc_req_id) = @_;

    my $orig_req_id = $self->{'_state'}->$access_method(
        $session,
        "invocation_call_req_id_$invoc_req_id",
    );

    if (!defined $orig_req_id) {
        die "Unrecognized YIELD request ID ($invoc_req_id)!"
    }

    my $orig_session = $self->{'_state'}->$access_method(
        $session,
        "invocation_call_session_$invoc_req_id",
    );

    return ($orig_req_id, $orig_session);
}

sub _receive_YIELD {
    my ($self, $session, $msg) = @_;

    my $invoc_req_id = $msg->get('Request');

    my $access_method = $msg->is_progress() ? 'get_session_property' : 'unset_session_property';

    my ($orig_req_id, $orig_session) = $self->_get_invocation_call_req_and_session(
        $access_method,
        $session,
        $invoc_req_id,
    );

    $self->_clear_call_invocation($session, $orig_req_id);

    $self->_send_RESULT(
        $orig_session,
        $orig_req_id,
        $msg->get('Metadata'),
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

sub _receive_CANCEL {
    my ($self, $session, $msg) = @_;

    my ($target_req_id, $target_session) = $self->_clear_call_invocation(
        $session,
        $msg->get('Request'),
    );

    $self->_create_and_send_ERROR(
        $session,
        'CALL',
        $msg->get('Request'),
        {},
        'wamp.error.canceled',
    );

    #The above will have set this to 1.
    $self->{'_prevent_custom_handler'} = 0;

    #XXX TODO
    if (!$target_req_id) {
use Data::Dumper;
print STDERR Dumper $self->{'_state'};
        die sprintf "No such (%s)!", $msg->get('Request');
    }

#Needed? Could wait for the ERROR response …
#XXX Memory leak attack?
#
#    $self->_get_invocation_call_req_and_session(
#        'unset_session_property',
#        $session,
#        $target_req_id,
#    );


    $self->_create_and_send_msg(
        $target_session,
        'INTERRUPT',
        $target_req_id,
        $msg->get('Metadata'),
    );

    return;
}

#----------------------------------------------------------------------

sub _validate_uri_or_send_ERROR {
    my ($self, $specimen, $session, $subtype, $req_id) = @_;

    my $ok;
    try {
        $self->_validate_uri($specimen);
        $ok = 1;
    }
    catch {
        $self->_create_and_send_ERROR(
            $session,
            $subtype,
            $req_id,
            {
                net_wamp_message => $_->get_message(),
            },
            'wamp.error.invalid_uri',
        );
    };

    return $ok;
}

1;
