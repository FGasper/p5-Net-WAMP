package Net::WAMP::Role::Base::Router;

use strict;
use warnings;

use Try::Tiny;

use parent qw(
    Net::WAMP::Role::Base::Peer
);

use Module::Load ();

use Net::WAMP::Messages ();
use Net::WAMP::Utils ();

sub new {
    my ($class, $state_obj) = @_;

    $state_obj ||= do {
        Module::Load::load('Net::WAMP::Role::Base::Router::State::Memory');
        Net::WAMP::Role::Base::Router::State::Memory->new();
    };

    return bless {
        _state => $state_obj,
    }, $class;
}

sub route_message {
    my ($self, $msg, $session) = @_;

    my ($handler_cr, $handler2_cr) = $self->_get_message_handlers($msg);

    my @extra_args = $handler_cr->( $self, $session, $msg );

    #Check for external method definition
    if ($handler2_cr) {
        $handler2_cr->( $self, $session, $msg, @extra_args );
    }

    return $msg;
}

sub forget_session {
    my ($self, $session) = @_;

    $self->{'_state'}->forget_session($session);

    return;
}

sub send_GOODBYE {
    my ($self, $session, $details, $reason) = @_;

    my $msg = $self->_create_and_send_msg(
        $session,
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

    return { roles => \%Net::WAMP::Role::Base::Router::Features::FEATURES };
}

#----------------------------------------------------------------------

sub _get_realm_for_session {
    my ($self, $session) = @_;

    return $self->{'_state'}->get_realm_for_session($session);
}

use constant _validate_HELLO => undef;

sub _receive_HELLO {
    my ($self, $session, $msg) = @_;

    my $session_id = Net::WAMP::Utils::generate_global_id();

    $self->_catch_pre_handshake_exception(
        $session,
        sub {
            if ($self->{'_state'}->session_exists($session)) {
                die "$self already received HELLO from $session!";
            }

            $self->_validate_HELLO($msg);

            $self->{'_state'}->add_session(
                $session,
                $msg->get('Realm') || do {
                    die "Missing “Realm” in HELLO!";  #XXX
                },
            );

            $self->{'_state'}->set_session_property(
                $session,
                'peer_roles',
                $msg->get('Details')->{'roles'} || do {
                    die "Missing “Details.roles” in HELLO!";  #XXX
                },
            );
        },
    );

    $self->{'_state'}->set_session_property(
        $session,
        'session_id',
        $session_id,
    );

    $self->_send_WELCOME($session, $session_id);

    return;
}

sub _send_WELCOME {
    my ($self, $session, $session_id) = @_;

    my $msg = $self->_create_and_send_msg(
        $session,
        'WELCOME',
        $session_id,
        $self->GET_DETAILS_HR(),
    );

    return $msg;
}

sub _receive_GOODBYE {
    my ($self, $session, $msg) = @_;

    $self->{'_state'}->forget_session($session);

    if (!$session->is_shut_down()) {
        $self->send_GOODBYE( $session, $msg->get('Details'), $msg->get('Reason') );
    }

    return $self;
}

#----------------------------------------------------------------------
# The actual logic to change router state is exposed publicly for the
# sake of applications that may want a “default” router configuration.



#----------------------------------------------------------------------

sub _create_and_send_msg {
    my ($self, $session, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg($name, @parts);

    $self->_send_msg($session, $msg);

    return $msg;
}

sub _create_and_send_session_msg {
    my ($self, $session, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg(
        $name,
        $session->get_next_session_scope_id(),
        @parts,
    );

    $self->_send_msg($session, $msg);

    return $msg;
}

sub _send_msg {
    my ($self, $session, $msg) = @_;

    #cache
    $self->{'_session_peer_groks_msg'}{$session}{$msg->get_type()} ||= do {
#        $self->_verify_receiver_can_accept_msg_type($msg->get_type());
        1;
    };

    $session->enqueue_message_to_send($msg);

    return $self;
}

#----------------------------------------------------------------------

sub _create_and_send_ERROR {
    my ($self, $session, $subtype, @args) = @_;

    return $self->_create_and_send_msg(
        $session,
        'ERROR',
        Net::WAMP::Messages::get_type_number($subtype),
        @args,
    );
}

sub _catch_exception {
    my ($self, $session, $req_type, $req_id, $todo_cr) = @_;

    my $ret;

    try {
        $ret = $todo_cr->();
    }
    catch {
        $self->_create_and_send_ERROR(
            $session,
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
    my ($self, $session, $todo_cr) = @_;

    my $ret;

    try {
        $ret = $todo_cr->();
    }
    catch {
        $self->_create_and_send_msg(
            $session,
            'ABORT',
            {
                message => "$_",
            },
            'net-wamp.error',
        );

        if ($self->{'_state'}->session_exists($session)) {
            $self->{'_state'}->forget_session($session);
        }
    };

    return $ret;
}

#----------------------------------------------------------------------
#XXX Copy/paste …

sub io_peer_is {
    my ($self, $session, $role) = @_;

    $self->_verify_handshake();

    return $self->{'_state'}->get_session_property($session, 'peer_roles')->{$role} ? 1 : 0;
}

sub io_peer_role_supports_boolean {
    my ($self, $session, $role, $feature) = @_;

    die "Need role!" if !length $role;
    die "Need feature!" if !length $feature;

    $self->_verify_handshake();

    my $peer_roles = $self->{'_state'}->get_session_property($session, 'peer_roles');

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
