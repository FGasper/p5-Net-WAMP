package Net::WAMP::Router;

use strict;
use warnings;

use Try::Tiny;

use parent qw(
    Net::WAMP::Peer
);

use Module::Load ();

use lib '/Users/felipe/code/p5-Protocol-WAMP/lib';
use Protocol::WAMP::Messages ();
use Protocol::WAMP::Utils ();

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
    my ($self, $msg, $io) = @_;

    my ($handler_cr, $handler2_cr) = $self->_get_message_handlers($msg);
use Data::Dumper;
print STDERR Dumper( (caller 0)[3], $msg );

    my @extra_args = $handler_cr->( $self, $io, $msg );

    #Check for external method definition
    if ($handler2_cr) {
$Data::Dumper::Deparse = 1;
print STDERR Dumper $handler2_cr;
        $handler2_cr->( $self, $io, $msg, @extra_args );
    }

    return $msg;
}

sub forget_io {
    my ($self, $io) = @_;

    $self->{'_state'}->remove_io($io);

    return;
}

sub send_GOODBYE {
    my ($self, $io, $details, $reason) = @_;

    my $msg = $self->_create_and_send_msg(
        $io,
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

sub _get_realm_for_io {
    my ($self, $io) = @_;

    return $self->{'_state'}->get_io_realm($io);
}

sub _receive_HELLO {
    my ($self, $io, $msg) = @_;

    if ($self->{'_state'}->io_exists($io)) {
        die "$self already received HELLO from $io!";
    }

    #TODO: validate HELLO

    $self->{'_state'}->add_io(
        $io,
        $msg->get('Realm') || do {
            die "Missing “Realm” in HELLO!";  #XXX
        },
    );

    $self->{'_state'}->set_io_property(
        $io,
        'peer_roles',
        $msg->get('Details')->{'roles'} || do {
            die "Missing “Details.roles” in HELLO!";  #XXX
        },
    );

    my $session_id = Protocol::WAMP::Utils::generate_global_id();

    $self->{'_state'}->set_io_property(
        $io,
        'session_id',
        $session_id,
    );

    $self->_send_WELCOME($io, $session_id);

    return;
}

sub _send_WELCOME {
    my ($self, $io, $session) = @_;

print STDERR "SENDING WELCOME\n";
    my $msg = $self->_create_and_send_msg(
        $io,
        'WELCOME',
        $session,
        $self->GET_DETAILS_HR(),
    );

    return $msg;
}

sub _receive_GOODBYE {
    my ($self, $io, $msg) = @_;

#    delete $self->{'_io_session'}{$io} or do {
#        die "Got GOODBYE without a registered session!";
#    };
#
#    delete $self->{'_io_realm'}{$io};

    $self->{'_state'}->remove_io($io);

    if ($self->{'_sent_GOODBYE'}) {
        $self->{'_finished'} = 1;
    }
    else {
        $self->send_GOODBYE( $io, $msg->get('Details'), $msg->get('Reason') );
    }

    return $self;
}

#----------------------------------------------------------------------
# The actual logic to change router state is exposed publicly for the
# sake of applications that may want a “default” router configuration.



#----------------------------------------------------------------------

sub _create_and_send_msg {
    my ($self, $io, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg($name, @parts);

    $self->_send_msg($io, $msg);

    return $msg;
}

sub _create_and_send_session_msg {
    my ($self, $io, $name, @parts) = @_;

    #This is in Peer.pm
    my $msg = $self->_create_msg(
        $name,
        $io->get_next_session_scope_id(),
        @parts,
    );

    $self->_send_msg($io, $msg);

    return $msg;
}

sub _send_msg {
    my ($self, $io, $msg) = @_;

    #if (!$self->{'_io_session'}{$io}) {
    #    die "Already finished!";    #XXX
    #}

    #cache
    $self->{'_io_peer_groks_msg'}{$io}{$msg->get_type()} ||= do {
#        $self->_verify_receiver_can_accept_msg_type($msg->get_type());
        1;
    };

    $io->write_wamp_message($msg);

    return $self;
}

#----------------------------------------------------------------------

sub _create_and_send_ERROR {
    my ($self, $io, $subtype, @args) = @_;

    return $self->_create_and_send_msg(
        $io,
        'ERROR',
        Protocol::WAMP::Messages::get_type_number($subtype),
        @args,
    );
}

sub _catch_exception {
    my ($self, $io, $req_type, $req_id, $todo_cr) = @_;

    my $ret;

    try {
        $ret = $todo_cr->();
    }
    catch {
        $self->_create_and_send_ERROR(
            $io,
            $req_type,
            $req_id,
            {},
            'net-wamp.error.exception',
            [ "$_" ],
        );
    };

    return $ret;
}

#----------------------------------------------------------------------
#XXX Copy/paste …

sub io_peer_is {
    my ($self, $io, $role) = @_;

    $self->_verify_handshake();

    return $self->{'_state'}->get_io_property($io, 'peer_roles')->{$role} ? 1 : 0;
}

sub io_peer_role_supports_boolean {
    my ($self, $io, $role, $feature) = @_;

    die "Need role!" if !length $role;
    die "Need feature!" if !length $feature;

    $self->_verify_handshake();

    my $peer_roles = $self->{'_state'}->get_io_property($io, 'peer_roles');

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
