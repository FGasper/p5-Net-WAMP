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

    my $realm = $self->_get_realm_for_io($io);

    if ( $self->{'_realm_procedure'}{$realm}{$procedure} ) {
        die "Already registered in “$realm”: “$procedure”";
    }

    my $registration = Protocol::WAMP::Utils::generate_global_id();

    $self->{'_realm_procedure'}{$realm}{$procedure} = {
        io => $io,
        options => $options,    #unused? See advanced
        registration => $registration,
    };

    $self->{'_realm_registration'}{$realm}{$registration} = $procedure;

    $self->{'_io_store'}{$io}{'_to_delete'}{"$realm-reg-$registration"} = [
        $self->{'_realm_registration'}{$realm}, $registration
    ];

    $self->{'_io_store'}{$io}{'_to_delete'}{"$realm-proc-$procedure"} = [
        $self->{'_realm_procedure'}{$realm}, $procedure
    ];

    return $registration;
}

sub unregister {
    my ($self, $io, $registration) = @_;

    my $realm = $self->_get_realm_for_io($io);

    my $procedure = delete $self->{'_realm_registration'}{$realm}{$registration} or do {
        die "No known registration in “$realm” for “$registration”!";
    };

    delete $self->{'_realm_procedure'}{$realm}{$procedure};

    delete $self->{'_io_store'}{$io}{'_to_delete'}{"$realm-reg-$registration"};
    delete $self->{'_io_store'}{$io}{'_to_delete'}{"$realm-proc-$procedure"};

    return;
}

#sub _get_target_io_for_procedure {
#    my ($self, $src_io, $procedure) = @_;
#
#    my $realm = $self->_get_realm_for_io($src_io);
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

    my $realm = $self->_get_realm_for_io($io);

    my $reg_hr = $self->{'_realm_procedure'}{$realm}{$procedure} or do {
        die "Unknown RPC procedure “$procedure” in realm “$realm”!";
    };

    my $target_io = $reg_hr->{'io'};

    my $msg2 = $self->_send_INVOCATION(
        $target_io,
        $reg_hr->{'registration'},
        {}, #TODO: determine support
        $msg->get('Arguments'),
        $msg->get('ArgumentsKw'),
    );

    $self->{'_io_store'}{$target_io}{'_invocation_call'}{ $msg2->get('Request') } = {
        req_id => $msg->get('Request'),
        io => $io,
    };

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

    my $orig_call_hr = delete $self->{'_io_store'}{$io}{'_invocation_call'}{$invoc_req_id} or do {
        die "Unrecognized YIELD request ID ($invoc_req_id)!"
    };

    $self->_send_RESULT(
        $orig_call_hr->{'io'},
        $orig_call_hr->{'req_id'},
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
