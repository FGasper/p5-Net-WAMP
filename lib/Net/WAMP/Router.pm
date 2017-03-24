package Net::WAMP::Router;

use strict;
use warnings;

use Try::Tiny;

use parent qw(
    Net::WAMP::Peer
);

use Module::Load ();

use Net::WAMP::Messages ();
use Net::WAMP::Utils ();

sub new {
    my ($class, $state_obj) = @_;

    $state_obj ||= do {
        Module::Load::load('Net::WAMP::Router::State::Memory');
        Net::WAMP::Router::State::Memory->new();
    };

    return bless {
        _state => $state_obj,
    }, $class;
}

sub route_message {
    my ($self, $msg, $tpt) = @_;

    my ($handler_cr, $handler2_cr) = $self->_get_message_handlers($msg);

    my @extra_args = $handler_cr->( $self, $tpt, $msg );

    #Check for external method definition
    if ($handler2_cr) {
        $handler2_cr->( $self, $tpt, $msg, @extra_args );
    }

    return $msg;
}

sub forget_transport {
    my ($self, $tpt) = @_;

    $self->{'_state'}->forget_transport($tpt);

    return;
}

sub send_GOODBYE {
    my ($self, $tpt, $details, $reason) = @_;

    my $msg = $self->_create_and_send_msg(
        $tpt,
        'GOODBYE',
        $details,
        $reason,
    );

    $self->{'_sent_GOODBYE'} = 1;

    return $msg;
}

#Subclasses can safely override. They’ll probably want to call into
#this one as well and Hash::Merge their contents.
sub GET_DETAILS_HR {
    my ($self) = @_;

    return { roles => \%Net::WAMP::Router::Features::FEATURES };
}

#----------------------------------------------------------------------

sub _get_realm_for_tpt {
    my ($self, $tpt) = @_;

    return $self->{'_state'}->get_transport_realm($tpt);
}

use constant _validate_HELLO => undef;

sub _receive_HELLO {
    my ($self, $tpt, $msg) = @_;

    $self->_catch_pre_handshake_exception(
        $tpt,
        sub {
            if ($self->{'_state'}->transport_exists($tpt)) {
                die "$self already received HELLO from $tpt!";
            }

            $self->_validate_HELLO($msg);

            $self->{'_state'}->add_transport(
                $tpt,
                $msg->get('Realm') || do {
                    die "Missing “Realm” in HELLO!";  #XXX
                },
            );

            $self->{'_state'}->set_transport_property(
                $tpt,
                'peer_roles',
                $msg->get('Details')->{'roles'} || do {
                    die "Missing “Details.roles” in HELLO!";  #XXX
                },
            );
        },
    );

    my $session_id = Net::WAMP::Utils::generate_global_id();

    $self->{'_state'}->set_transport_property(
        $tpt,
        'session_id',
        $session_id,
    );

    $self->_send_WELCOME($tpt, $session_id);

    return;
}

sub _send_WELCOME {
    my ($self, $tpt, $session) = @_;

    my $msg = $self->_create_and_send_msg(
        $tpt,
        'WELCOME',
        $session,
        $self->GET_DETAILS_HR(),
    );

    return $msg;
}

sub _receive_GOODBYE {
    my ($self, $tpt, $msg) = @_;

    $self->{'_state'}->forget_transport($tpt);

    if ($self->{'_sent_GOODBYE'}) {
        $self->{'_finished'} = 1;
    }
    else {
        $self->send_GOODBYE( $tpt, $msg->get('Details'), $msg->get('Reason') );
    }

    return $self;
}

#----------------------------------------------------------------------
# The actual logic to change router state is exposed publicly for the
# sake of applications that may want a “default” router configuration.



#----------------------------------------------------------------------

sub _create_and_send_msg {
    my ($self, $tpt, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg($name, @parts);

    $self->_send_msg($tpt, $msg);

    return $msg;
}

sub _create_and_send_session_msg {
    my ($self, $tpt, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg(
        $name,
        $tpt->get_next_session_scope_id(),
        @parts,
    );

    $self->_send_msg($tpt, $msg);

    return $msg;
}

sub _send_msg {
    my ($self, $tpt, $msg) = @_;

    #cache
    $self->{'_tpt_peer_groks_msg'}{$tpt}{$msg->get_type()} ||= do {
#        $self->_verify_receiver_can_accept_msg_type($msg->get_type());
        1;
    };

    $tpt->write_wamp_message($msg);

    return $self;
}

#----------------------------------------------------------------------

sub _create_and_send_ERROR {
    my ($self, $tpt, $subtype, @args) = @_;

    return $self->_create_and_send_msg(
        $tpt,
        'ERROR',
        Net::WAMP::Messages::get_type_number($subtype),
        @args,
    );
}

sub _catch_exception {
    my ($self, $tpt, $req_type, $req_id, $todo_cr) = @_;

    my $ret;

    try {
        $ret = $todo_cr->();
    }
    catch {
        $self->_create_and_send_ERROR(
            $tpt,
            $req_type,
            $req_id,
            {},
            'net-wamp.error',
            [ "$_" ],
        );
    };

    return $ret;
}

sub _catch_pre_handshake_exception {
    my ($self, $tpt, $todo_cr) = @_;

    my $ret;

    try {
        $ret = $todo_cr->();
    }
    catch {
        $self->_create_and_send_msg(
            $tpt,
            'ABORT',
            {
                message => "$_",
            },
            'net-wamp.error',
        );

        if ($self->{'_state'}->transport_exists($tpt)) {
            $self->{'_state'}->forget_transport($tpt);
        }
    };

    return $ret;
}

#----------------------------------------------------------------------
#XXX Copy/paste …

sub io_peer_is {
    my ($self, $tpt, $role) = @_;

    $self->_verify_handshake();

    return $self->{'_state'}->get_transport_property($tpt, 'peer_roles')->{$role} ? 1 : 0;
}

sub io_peer_role_supports_boolean {
    my ($self, $tpt, $role, $feature) = @_;

    die "Need role!" if !length $role;
    die "Need feature!" if !length $feature;

    $self->_verify_handshake();

    my $peer_roles = $self->{'_state'}->get_transport_property($tpt, 'peer_roles');

    if ( my $rolfeat = $peer_roles->{$role} ) {
        if ( my $features_hr = $rolfeat->{'features'} ) {
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

1;
