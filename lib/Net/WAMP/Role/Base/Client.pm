package Net::WAMP::Role::Base::Client;

use strict;
use warnings;

use Module::Load ();

use parent qw( Net::WAMP::Role::Base::Peer );

use Net::WAMP::Session ();

use Net::WAMP::Role::Base::Client::Features ();
use Net::WAMP::X ();

sub send_HELLO {
    my ($self, $realm, $details_hr_in) = @_;

    my $details_hr = $self->GET_DETAILS_HR();

    if ($details_hr_in) {
        Module::Load::load('Hash::Merge');
        $details_hr = Hash::Merge::merge( $details_hr, $details_hr_in );
    }

    return $self->_create_and_send_msg( 'HELLO', $realm, $details_hr );
}

#Subclasses can safely override. They’ll probably want to call into
#this one as well and Hash::Merge their contents.
sub GET_DETAILS_HR {
    my ($self) = @_;

    return { roles => \%Net::WAMP::Role::Base::Client::Features::FEATURES };
}

#----------------------------------------------------------------------

sub _receive_WELCOME {
    my ($self, $msg) = @_;

    if ( $self->{'_peer_roles'} ) {
        die "Already received WELCOME!";    #XXX
    }

    $self->{'_peer_roles'} = $msg->get('Details')->{'roles'} or do {
        die "Missing “Details.roles” in WELCOME!";  #XXX
    };

    $self->{'_session_id'} = $msg->get('Session') or do {
        die "Missing “Session” in WELCOME!";  #XXX
    };

    $self->{'_handshake_done'} = 1;

    return;
}

sub _receive_GOODBYE {
    my ($self, $msg) = @_;

    $self->{'_received_goodbye'} = 1;

    if ($self->{'_sent_goodbye'}) {
        $self->{'_finished'} = 1;
    }
    else {
        $self->send_GOODBYE( $msg->get('Details'), $msg->get('Reason') );
    }

    return $self;
}

#----------------------------------------------------------------------
# The below were originally in Peer.pm …
#----------------------------------------------------------------------

#serialization
sub new {
    my ($class, %opts) = @_;

    my $self = {
        _session => Net::WAMP::Session->new(%opts),
    };

    return bless $self, $class;
}

sub message_object_to_bytes {
    my ($self, $wamp_msg) = @_;

    return $self->{'_session'}->message_object_to_bytes($wamp_msg);
}

sub handle_message {
    my ($self) = @_;

    my $msg = $self->{'_session'}->message_bytes_to_object($_[1]);

    my ($handler_cr, $handler2_cr) = $self->_get_message_handlers($msg);

    my @extra_args = $handler_cr->( $self, $msg );

    #Check for external method definition
    if ($handler2_cr) {
        $handler2_cr->( $self, $msg, @extra_args );
    }

    return $msg;
}

sub send_ABORT {
    my ($self, $details_hr, $reason) = @_;

    return $self->_create_and_send_msg( 'ABORT', $details_hr, $reason );
}

sub send_GOODBYE {
    my ($self, $details_hr, $reason) = @_;

    my $msg = $self->_create_and_send_msg( 'GOODBYE', $details_hr, $reason );

    $self->{'_sent_goodbye'} = 1;

    if ($self->{'_received_goodbye'}) {
        $self->{'_finished'} = 1;
    }

    return $msg;
}

#----------------------------------------------------------------------

sub peer_is {
    my ($self, $role) = @_;

    $self->_verify_handshake();

    return $self->{'_peer_roles'}{$role} ? 1 : 0;
}

sub peer_role_supports_boolean {
    my ($self, $role, $feature) = @_;

    die "Need role!" if !length $role;
    die "Need feature!" if !length $feature;

    $self->_verify_handshake();

    if ( my $brk = $self->{'_peer_roles'}{$role} ) {
        if ( my $features_hr = $brk->{'features'} ) {
            my $val = $features_hr->{$feature};
            return 0 if !defined $val;

            if (!$val->isa('Types::Serialiser::Boolean')) {
                die "“$role”/“$feature” ($val) is not a boolean value!";
            }

            return $val ? 1 : 0;
        }
    }

    return 0;
}

#----------------------------------------------------------------------

sub _create_and_send_msg {
    my ($self, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg($name, @parts);

    $self->_send_msg($msg);

    return $msg;
}

sub _create_and_send_session_msg {
    my ($self, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg(
        $name,
        $self->{'_session'}->get_next_session_scope_id(),
        @parts,
    );

    $self->_send_msg($msg);

    return $msg;
}

sub _send_msg {
    my ($self, $msg) = @_;

    if ($self->{'_finished'}) {
        die "Already finished!";    #XXX
    }

    #cache
    $self->{'_peer_groks_msg'}{$msg->get_type()} ||= do {
#        $self->_verify_receiver_can_accept_msg_type($msg->get_type());
        1;
    };

    $self->{'_session'}->send_message($msg);

    return;
}

sub _receive_ERROR {
    my ($self, $msg) = @_;

    my $subtype = $msg->get_request_type();
    my $subhandler_n = "_receive_ERROR_$subtype";

    return $self->$subhandler_n($msg);
}

sub _verify_receiver_can_accept_msg_type {
    my ($self, $msg_type) = @_;

    my $role;

    if (my $cr = $self->can("receiver_role_of_$msg_type")) {
        my $role = $cr->();

        if (!$self->peer_is( $role )) {
            die Net::WAMP::X->create(
                'PeerLacksMessageRecipientRole',
                $msg_type,
                $role,
            );
        }

        if (my $cr = $self->can("receiver_feature_of_$msg_type")) {
            if (!$self->peer_role_supports_boolean( $role, $cr->() )) {
                my $feature_name = $cr->();
                die Net::WAMP::X->create(
                    'PeerLacksMessageRecipientFeature',
                    $msg_type,
                    $feature_name,
                );
            }
        }
    }

    return;
}

1;
